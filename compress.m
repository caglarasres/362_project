% compress.m
clearvars;

% --- Parameters ---
GOP_size = 15; % Example: 1 I-frame, 14 P-frames. Change as needed for testing.
video_data_folder = './video_data/'; 
output_binary_file = 'result.bin';
FRAME_HEIGHT = 360;
FRAME_WIDTH = 480;
MB_SIZE = 8;

% Quantization Matrix (from Figure 2 of project description)
Q_matrix = [
    16 11 10 16 24  40  51  61;
    12 12 14 19 26  58  60  55;
    14 13 16 24 40  57  69  56;
    14 17 22 29 51  87  80  62;
    18 22 37 56 68 109 103  77;
    24 35 55 64 81 104 113  92;
    49 64 78 87 103 121 120 101;
    72 92 95 98 112 100 103  99
];

fprintf('Loading frame list...\n');
frame_files = dir(fullfile(video_data_folder, '*.jpg'));
if isempty(frame_files)
    error('No JPG files found in %s. Please create/populate it (e.g., frame_001.jpg, frame_002.jpg, ...)', video_data_folder);
end
% Sort frame files by name to ensure correct order
[~,sorted_indices] = sort({frame_files.name});
frame_files = frame_files(sorted_indices);

num_frames_available = length(frame_files);
% You can limit num_frames for testing:
num_frames_to_process = num_frames_available; % Process all available frames
% num_frames_to_process = 5; % For example, process only 5 frames for quick test

fprintf('Found %d frames. Processing %d frames.\n', num_frames_available, num_frames_to_process);


% --- "Warm-up" persistent variables in custom DCT/IDCT ---
% This ensures the DCT transformation matrices are computed once before heavy looping.
if num_frames_to_process > 0 
    dummy_block = zeros(MB_SIZE, MB_SIZE);
    my_dct2(dummy_block); % Call to cache T in my_dct2
    my_idct2(dummy_block); % Call to cache T and T' in my_idct2
    fprintf('DCT/IDCT helper functions initialized.\n');
end


% --- Prepare for Encoding ---
fid = fopen(output_binary_file, 'wb');
if fid == -1
    error('Could not open file %s for writing.', output_binary_file);
end

% Write header: num_frames_to_process, height, width, GOP_size
fwrite(fid, uint16(num_frames_to_process), 'uint16');
fwrite(fid, uint16(FRAME_HEIGHT), 'uint16');
fwrite(fid, uint16(FRAME_WIDTH), 'uint16');
fwrite(fid, uint8(GOP_size), 'uint8'); 

previous_reconstructed_frame_double_clipped = []; % For P-frame prediction (clipped values)
mb_rows = FRAME_HEIGHT / MB_SIZE;
mb_cols = FRAME_WIDTH / MB_SIZE;

fprintf('Starting compression...\n');
tic_total_compression = tic; % Start timer for overall compression

for frame_idx = 1:num_frames_to_process
    tic_frame = tic; % Timer for processing this single frame
    
    % 1. Read frame
    current_frame_rgb_uint8 = imread(fullfile(video_data_folder, frame_files(frame_idx).name));
    current_frame_double = double(current_frame_rgb_uint8); % Work with double for precision

    % Determine frame type
    is_iframe = (mod(frame_idx - 1, GOP_size) == 0);
    
    fwrite(fid, uint8(is_iframe), 'uint8'); % 1 for I-frame, 0 for P-frame

    % 2. Divide into macroblocks (original current frame)
    mb_cells_current_orig = frame_to_mb(current_frame_double);
    
    % To store reconstructed macroblocks for the current frame (for P-frame prediction reference)
    reconstructed_mb_cells_for_current_frame = cell(mb_rows, mb_cols);

    % OPTIMIZATION: For P-frames, get all macroblocks of the *previous reconstructed frame* ONCE
    prev_mb_cells_reconstructed_all = []; % Initialize for clarity
    if ~is_iframe % If it's a P-frame
        if isempty(previous_reconstructed_frame_double_clipped)
            error('Previous reconstructed frame not available for P-frame %d encoding.', frame_idx);
        end
        prev_mb_cells_reconstructed_all = frame_to_mb(previous_reconstructed_frame_double_clipped);
    end

    for r = 1:mb_rows
        for c = 1:mb_cols
            % This will hold the R,G,B channels of the reconstructed macroblock at (r,c)
            reconstructed_mb_one_colorplane_channels = zeros(MB_SIZE, MB_SIZE, 3); 

            for channel = 1:3 % Process R, G, B channels separately
                mb_channel_data_orig = mb_cells_current_orig{r, c}(:,:,channel);
                
                target_mb_data_for_dct = []; % Data that will be DCT'd (either original MB or residual)
                
                % --- I-Frame or P-Frame specific processing ---
                if is_iframe
                    target_mb_data_for_dct = mb_channel_data_orig; % Process the macroblock directly
                else % P-Frame: Compute residual
                    % Use the pre-sliced macroblock from the previous reconstructed frame
                    prev_mb_channel_data_reconstructed = prev_mb_cells_reconstructed_all{r,c}(:,:,channel);
                    target_mb_data_for_dct = mb_channel_data_orig - prev_mb_channel_data_reconstructed; % Residual
                end

                % 3. Apply DCT (custom)
                dct_coeffs = my_dct2(target_mb_data_for_dct);
                
                % 4. Quantize
                quantized_coeffs = round(dct_coeffs ./ Q_matrix);
                
                % 5. Zigzag Scan
                zigzag_vector = zigzag_scan(quantized_coeffs);
                
                % 6. Run-Length Encoding
                rle_data = run_length_encode(zigzag_vector);
                
                % --- Serialize and write RLE data ---
                num_rle_pairs = 0;
                if ~isempty(rle_data)
                    num_rle_pairs = size(rle_data, 1);
                end
                fwrite(fid, uint16(num_rle_pairs), 'uint16');
                if num_rle_pairs > 0
                    fwrite(fid, int16(rle_data(:,1)'), 'int16'); % RLE runs (as per our RLE, 1 for non-zero, count for zero)
                    fwrite(fid, int16(rle_data(:,2)'), 'int16');  % RLE values (DCT coeffs can be negative)
                end
                
                % --- Reconstruct this macroblock channel for P-Frame prediction reference ---
                dequantized_coeffs = quantized_coeffs .* Q_matrix;
                reconstructed_processed_data = my_idct2(dequantized_coeffs); % This is I-frame data or P-frame residual
                
                if is_iframe
                    reconstructed_mb_one_colorplane_channels(:,:,channel) = reconstructed_processed_data;
                else % P-Frame: Add residual back to the *reconstructed* previous macroblock
                    prev_mb_channel_data_reconstructed = prev_mb_cells_reconstructed_all{r,c}(:,:,channel); % Get it again for addition
                    reconstructed_mb_one_colorplane_channels(:,:,channel) = reconstructed_processed_data + prev_mb_channel_data_reconstructed;
                end
            end % End channel loop
            reconstructed_mb_cells_for_current_frame{r,c} = reconstructed_mb_one_colorplane_channels;
        end % End macroblock col loop
    end % End macroblock row loop
    
    % Assemble the fully reconstructed current frame (double, not clipped yet)
    current_reconstructed_frame_double_unclipped = mb_to_frame(reconstructed_mb_cells_for_current_frame);
    
    % Store for next P-frame prediction (MUST BE CLIPPED, as this is what would be "displayed" or saved)
    previous_reconstructed_frame_double_clipped = max(0, min(255, current_reconstructed_frame_double_unclipped));
    
    time_taken_for_frame = toc(tic_frame);
    fprintf('Frame %d/%d processed in %.2f seconds.\n', frame_idx, num_frames_to_process, time_taken_for_frame);

end % End frame loop

total_compression_time_seconds = toc(tic_total_compression);
fprintf('Total compression of %d frames finished in %.2f seconds (%.2f minutes).\n', ...
        num_frames_to_process, total_compression_time_seconds, total_compression_time_seconds/60);
fclose(fid);

% --- Calculate and display compression ratio (optional here, part of deliverables) ---
file_info_bin = dir(output_binary_file);
if ~isempty(file_info_bin)
    compressed_size_bytes = file_info_bin.bytes;
    if compressed_size_bytes > 0
        uncompressed_size_bits = num_frames_to_process * FRAME_HEIGHT * FRAME_WIDTH * 3 * 8; % 3 channels, 8 bits/channel
        compression_ratio_val = uncompressed_size_bits / (compressed_size_bytes * 8);
        fprintf('Uncompressed size (for %d frames): %.2f MB\n', num_frames_to_process, uncompressed_size_bits / (8*1024*1024));
        fprintf('Compressed size: %.2f MB (%.0f bytes)\n', compressed_size_bytes / (1024*1024), compressed_size_bytes);
        fprintf('Compression Ratio: %.2f : 1\n', compression_ratio_val);
    else
        fprintf('Compressed file size is 0 bytes. Cannot calculate compression ratio.\n');
    end
else
    fprintf('Could not get size of %s to calculate compression ratio.\n', output_binary_file);
end

% Clear persistent variables in custom DCT/IDCT if script is run multiple times 
% or if these functions are used elsewhere with different N.
clear my_dct2 my_idct2 