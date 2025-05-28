% decompress.m
clearvars;

% --- Parameters ---
input_binary_file = 'result.bin'; % Ensure this matches the output of compress.m
decompressed_folder = './decompressed/';
MB_SIZE = 8;

% Quantization Matrix (must be same as encoder)
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

% --- Create output folder if it doesn't exist ---
if ~exist(decompressed_folder, 'dir')
   mkdir(decompressed_folder);
   fprintf('Created decompressed folder: %s\n', decompressed_folder);
end

% --- "Warm-up" persistent variables in custom IDCT ---
% (my_dct2 is not used in decompress, only my_idct2 and its dependency my_dct_matrix)
if MB_SIZE > 0 % A simple condition to ensure it runs once
    dummy_block = zeros(MB_SIZE, MB_SIZE);
    my_idct2(dummy_block); % Call to cache T and T' in my_idct2
    fprintf('IDCT helper function initialized.\n');
end

% --- Prepare for Decompression ---
fid = fopen(input_binary_file, 'rb');
if fid == -1
    error('Could not open file %s for reading.', input_binary_file);
end

% Read header
num_frames = fread(fid, 1, 'uint16');
FRAME_HEIGHT = fread(fid, 1, 'uint16');
FRAME_WIDTH = fread(fid, 1, 'uint16');
GOP_size_from_file = fread(fid, 1, 'uint8'); % Read GOP, though per-frame type is primary

fprintf('Decompressing video: %d frames, %dx%d. GOP (from file): %d\n', num_frames, FRAME_WIDTH, FRAME_HEIGHT, GOP_size_from_file);

previous_reconstructed_frame_double_clipped = []; % For P-frame reconstruction
mb_rows_count = FRAME_HEIGHT / MB_SIZE;
mb_cols_count = FRAME_WIDTH / MB_SIZE;

fprintf('Starting decompression...\n');
tic_total_decompression = tic; % Start timer for overall decompression

for frame_idx = 1:num_frames
    tic_frame_decompress = tic; % Timer for this frame's decompression
    
    if feof(fid)
        error('Unexpected end of file while trying to read frame type for frame %d.', frame_idx);
    end
    is_iframe_encoded = fread(fid, 1, 'uint8'); 
    is_iframe = (is_iframe_encoded == 1);

    current_reconstructed_mb_cells = cell(mb_rows_count, mb_cols_count);

    % OPTIMIZATION: For P-frames, get all macroblocks of the *previous reconstructed frame* ONCE
    prev_mb_cells_reconstructed_all_decompress = []; % Initialize for clarity
    if ~is_iframe % If it's a P-frame
        if isempty(previous_reconstructed_frame_double_clipped)
            error('Previous reconstructed frame not available for P-frame %d decoding.', frame_idx);
        end
        prev_mb_cells_reconstructed_all_decompress = frame_to_mb(previous_reconstructed_frame_double_clipped);
    end

    for r = 1:mb_rows_count
        for c = 1:mb_cols_count
            reconstructed_mb_one_colorplane_channels = zeros(MB_SIZE, MB_SIZE, 3); % double
            
            for channel = 1:3
                if feof(fid)
                     error('Unexpected end of file while reading RLE data for frame %d, MB(%d,%d), Ch %d.', frame_idx, r, c, channel);
                end
                num_rle_pairs = fread(fid, 1, 'uint16');
                rle_data = [];
                if num_rle_pairs > 0
                    % Check if enough data is available for reading RLE pairs
                    bytes_needed_for_rle = num_rle_pairs * (2 + 2); % 2 bytes for run (int16), 2 for val (int16)
                    current_pos = ftell(fid);
                    fseek(fid, 0, 'eof');
                    eof_pos = ftell(fid);
                    fseek(fid, current_pos, 'bof'); % Return to current position
                    
                    if (current_pos + bytes_needed_for_rle > eof_pos)
                        error('Unexpected end of file or insufficient data for RLE pairs. Frame %d, MB(%d,%d), Ch %d. Expected %d pairs (%d bytes), available ~%d bytes.', ...
                              frame_idx, r, c, channel, num_rle_pairs, bytes_needed_for_rle, eof_pos - current_pos);
                    end
                    runs = fread(fid, num_rle_pairs, 'int16'); % Read as int16 (matched encoder's write)
                    vals = fread(fid, num_rle_pairs, 'int16'); % Read as int16 (matched encoder's write)
                    rle_data = [runs, vals];
                end
                
                % 1. Run-Length Decode
                zigzag_vector_retrieved = run_length_decode(rle_data, MB_SIZE*MB_SIZE);
                
                % 2. Inverse Zigzag Scan
                quantized_coeffs_retrieved = inverse_zigzag_scan(zigzag_vector_retrieved);
                
                % 3. Dequantize
                dequantized_coeffs = quantized_coeffs_retrieved .* Q_matrix;
                
                % 4. Inverse DCT (custom)
                idct_reconstructed_data = my_idct2(dequantized_coeffs); % This is either full MB data (I-frame) or residual (P-frame)
                
                if is_iframe
                    reconstructed_mb_one_colorplane_channels(:,:,channel) = idct_reconstructed_data;
                else % P-Frame: Add residual to corresponding *reconstructed* previous macroblock
                    % Use the pre-sliced macroblock from the previous reconstructed frame
                    prev_mb_channel_data_reconstructed = prev_mb_cells_reconstructed_all_decompress{r,c}(:,:,channel);
                    reconstructed_mb_one_colorplane_channels(:,:,channel) = idct_reconstructed_data + prev_mb_channel_data_reconstructed;
                end
            end % End channel loop
            current_reconstructed_mb_cells{r,c} = reconstructed_mb_one_colorplane_channels;
        end % End macroblock col loop
    end % End macroblock row loop
    
    % Assemble the full frame from macroblocks
    reconstructed_frame_double_unclipped = mb_to_frame(current_reconstructed_mb_cells);
    
    % Clip to [0, 255] for saving and for next P-frame reference
    reconstructed_frame_double_clipped_for_saving = max(0, min(255, reconstructed_frame_double_unclipped));
    reconstructed_frame_uint8 = uint8(reconstructed_frame_double_clipped_for_saving);
    
    % Save frame
    output_frame_filename = fullfile(decompressed_folder, sprintf('frame_%03d.jpg', frame_idx));
    try
        imwrite(reconstructed_frame_uint8, output_frame_filename, 'jpg', 'Quality', 95); % Save as JPG
    catch ME
        warning('Could not write frame %s. Error: %s. Skipping this frame.', output_frame_filename, ME.message);
    end
    
    % Store for next P-frame (MUST BE THE SAME CLIPPED DOUBLE values as used in encoder and as saved)
    previous_reconstructed_frame_double_clipped = reconstructed_frame_double_clipped_for_saving; 

    time_taken_for_frame_decompress = toc(tic_frame_decompress);
    fprintf('Frame %d/%d decompressed and saved in %.2f seconds.\n', frame_idx, num_frames, time_taken_for_frame_decompress);

end % End frame loop

total_decompression_time_seconds = toc(tic_total_decompression);
fprintf('Total decompression of %d frames finished in %.2f seconds (%.2f minutes).\n', ...
        num_frames, total_decompression_time_seconds, total_decompression_time_seconds/60);
fclose(fid);
fprintf('Decompression finished. Output frames in: %s\n', decompressed_folder);

% Clear persistent variables
clear my_idct2 my_dct_matrix % my_dct_matrix is used by my_idct2