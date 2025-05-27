% compress.m
clearvars; clc;

% --- Parameters ---
GOP_size = 15; % Example: 1 I-frame, 14 P-frames
video_data_folder = './video_data/'; % Ensure this folder exists and contains JPGs
output_binary_file = 'result.bin';
FRAME_HEIGHT = 360;
FRAME_WIDTH = 480;
MB_SIZE = 8;

% Quantization Matrix
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

% --- Get list of frames ---
frame_files = dir(fullfile(video_data_folder, '*.jpg'));
if isempty(frame_files)
    error('No JPG files found in %s. Please create/populate it (e.g., frame_001.jpg, frame_002.jpg, ...)', video_data_folder);
end
num_frames = length(frame_files);
fprintf('Found %d frames.\n', num_frames);

% --- Prepare for Encoding ---
fid = fopen(output_binary_file, 'wb');
if fid == -1
    error('Could not open file %s for writing.', output_binary_file);
end

% Write header: num_frames, height, width, GOP_size (important for decoder)
fwrite(fid, num_frames, 'uint16');
fwrite(fid, FRAME_HEIGHT, 'uint16');
fwrite(fid, FRAME_WIDTH, 'uint16');
fwrite(fid, GOP_size, 'uint8'); % GOP size

previous_reconstructed_frame_double = []; % For P-frame prediction

fprintf('Starting compression...\n');
for frame_idx = 1:num_frames
    fprintf('Processing frame %d/%d...\n', frame_idx, num_frames);
    
    % 1. Read frame
    current_frame_rgb = imread(fullfile(video_data_folder, frame_files(frame_idx).name));
    current_frame_double = double(current_frame_rgb); % Work with double for precision

    % Determine frame type
    is_iframe = (mod(frame_idx - 1, GOP_size) == 0);
    
    fwrite(fid, uint8(is_iframe), 'uint8'); % 1 for I-frame, 0 for P-frame

    % 2. Divide into macroblocks
    mb_cells_current = frame_to_mb(current_frame_double);
    [mb_rows, mb_cols] = size(mb_cells_current);
    
    % Store reconstructed macroblocks for the current frame (for P-frame prediction)
    reconstructed_mb_cells_current_frame = cell(mb_rows, mb_cols);

    for r = 1:mb_rows
        for c = 1:mb_cols
            original_mb = mb_cells_current{r, c}; % 8x8x3 double
            processed_mb_channels = zeros(MB_SIZE, MB_SIZE, 3);
            reconstructed_mb_channels = zeros(MB_SIZE, MB_SIZE, 3);

            for channel = 1:3 % Process R, G, B channels separately
                mb_channel_data = original_mb(:,:,channel);
                
                % --- I-Frame or P-Frame specific processing ---
                if is_iframe
                    target_mb_data = mb_channel_data; % Process the macroblock directly
                else
                    if isempty(previous_reconstructed_frame_double)
                        error('Previous reconstructed frame not available for P-frame encoding.');
                    end
                    % P-Frame: Compute residual
                    prev_mb_cells = frame_to_mb(previous_reconstructed_frame_double);
                    prev_mb_channel_data = prev_mb_cells{r,c}(:,:,channel);
                    target_mb_data = mb_channel_data - prev_mb_channel_data; % Residual
                end

                % 3. Apply DCT
                dct_coeffs = dct2(target_mb_data);
                
                % 4. Quantize
                quantized_coeffs = round(dct_coeffs ./ Q_matrix);
                
                % 5. Zigzag Scan
                zigzag_vector = zigzag_scan(quantized_coeffs);
                
                % 6. Run-Length Encoding
                rle_data = run_length_encode(zigzag_vector);
                
                % --- Serialize and write RLE data ---
                % Store number of RLE pairs, then the pairs themselves
                % Ensure rle_data is not empty before getting its size
                if isempty(rle_data)
                    num_rle_pairs = 0;
                else
                    num_rle_pairs = size(rle_data, 1);
                end
                fwrite(fid, uint16(num_rle_pairs), 'uint16');
                if num_rle_pairs > 0
                    % RLE data: first column is run (can be > 255), second is value (can be negative)
                    fwrite(fid, rle_data(:,1)', 'uint16'); % Assuming runs won't exceed 65535 (for 8x8, max run is 64)
                    fwrite(fid, rle_data(:,2)', 'int16');  % DCT coeffs can be negative
                end
                
                % --- For P-Frame prediction: Reconstruct this macroblock channel ---
                % (Decoder will do this, encoder does it to have reference for next P-frame)
                dequantized_coeffs = quantized_coeffs .* Q_matrix;
                reconstructed_dct_residual_or_iframe = idct2(dequantized_coeffs);
                
                if is_iframe
                    reconstructed_mb_channels(:,:,channel) = reconstructed_dct_residual_or_iframe;
                else
                    % Add residual back to the *reconstructed* previous macroblock
                    prev_mb_cells_rec = frame_to_mb(previous_reconstructed_frame_double); % Re-slice the previous reconstructed frame
                    reconstructed_mb_channels(:,:,channel) = reconstructed_dct_residual_or_iframe + prev_mb_cells_rec{r,c}(:,:,channel);
                end
            end % End channel loop
            reconstructed_mb_cells_current_frame{r,c} = reconstructed_mb_channels;
        end % End macroblock col loop
    end % End macroblock row loop
    
    % Assemble the fully reconstructed current frame (double, not clipped yet)
    current_reconstructed_frame_double = mb_to_frame(reconstructed_mb_cells_current_frame);
    
    % Store for next P-frame prediction
    % Important: Clip here because the previous frame the P-frame refers to
    % would have been a displayable (and thus clipped) image.
    previous_reconstructed_frame_double = max(0, min(255, current_reconstructed_frame_double));

end % End frame loop

fclose(fid);
fprintf('Compression finished. Output: %s\n', output_binary_file);

% --- Calculate and display compression ratio (optional here, part of deliverables) ---
info_bin = dir(output_binary_file);
compressed_size_bits = info_bin.bytes * 8;
uncompressed_size_bits = num_frames * FRAME_HEIGHT * FRAME_WIDTH * 3 * 8; % 3 channels, 8 bits/channel
compression_ratio = uncompressed_size_bits / compressed_size_bits;
fprintf('Uncompressed size: %.2f MB\n', uncompressed_size_bits / (8*1024*1024));
fprintf('Compressed size: %.2f MB\n', compressed_size_bits / (8*1024*1024));
fprintf('Compression Ratio: %.2f : 1\n', compression_ratio);

% --- Important Notes from project ---
% - Your video data is 480x360, 120 frames, 24 bits/pixel = ~62MB raw.
% - Test binary was 7.8MB with GOP 30. Check your sizes.