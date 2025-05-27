% decompress.m
clearvars; clc;

% --- Parameters ---
input_binary_file = 'result.bin';
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
GOP_size = fread(fid, 1, 'uint8'); % Not strictly needed by decoder if frame type is stored per frame

fprintf('Found %d frames in binary. Dimensions: %dx%d. GOP size (from file): %d\n', num_frames, FRAME_WIDTH, FRAME_HEIGHT, GOP_size);

previous_reconstructed_frame_double = []; % For P-frame reconstruction

mb_rows_count = FRAME_HEIGHT / MB_SIZE;
mb_cols_count = FRAME_WIDTH / MB_SIZE;

fprintf('Starting decompression...\n');
for frame_idx = 1:num_frames
    fprintf('Decompressing frame %d/%d...\n', frame_idx, num_frames);
    
    is_iframe_encoded = fread(fid, 1, 'uint8'); % 1 for I-frame, 0 for P-frame
    is_iframe = (is_iframe_encoded == 1);

    current_reconstructed_mb_cells = cell(mb_rows_count, mb_cols_count);

    for r = 1:mb_rows_count
        for c = 1:mb_cols_count
            reconstructed_mb_channels = zeros(MB_SIZE, MB_SIZE, 3); % double
            
            for channel = 1:3
                % --- Deserialize RLE data ---
                num_rle_pairs = fread(fid, 1, 'uint16');
                rle_data = [];
                if num_rle_pairs > 0
                    runs = fread(fid, num_rle_pairs, 'uint16');
                    vals = fread(fid, num_rle_pairs, 'int16');
                    rle_data = [runs, vals];
                end
                
                % 1. Run-Length Decode
                zigzag_vector_retrieved = run_length_decode(rle_data, MB_SIZE*MB_SIZE);
                
                % 2. Inverse Zigzag Scan
                quantized_coeffs_retrieved = inverse_zigzag_scan(zigzag_vector_retrieved);
                
                % 3. Dequantize
                dequantized_coeffs = quantized_coeffs_retrieved .* Q_matrix;
                
                % 4. Inverse DCT
                idct_reconstructed_data = idct2(dequantized_coeffs); % This is either full MB data (I-frame) or residual (P-frame)
                
                if is_iframe
                    reconstructed_mb_channels(:,:,channel) = idct_reconstructed_data;
                else
                    if isempty(previous_reconstructed_frame_double)
                        error('Previous reconstructed frame not available for P-frame decoding.');
                    end
                    % P-Frame: Add residual to corresponding *reconstructed* previous macroblock
                    prev_mb_cells = frame_to_mb(previous_reconstructed_frame_double); % Slice from previous reconstructed frame
                    reconstructed_mb_channels(:,:,channel) = idct_reconstructed_data + prev_mb_cells{r,c}(:,:,channel);
                end
            end % End channel loop
            current_reconstructed_mb_cells{r,c} = reconstructed_mb_channels;
        end % End macroblock col loop
    end % End macroblock row loop
    
    % Assemble the full frame from macroblocks
    reconstructed_frame_double = mb_to_frame(current_reconstructed_mb_cells);
    
    % Clip to [0, 255] and convert to uint8 for saving
    reconstructed_frame_uint8 = uint8(max(0, min(255, reconstructed_frame_double)));
    
    % Save frame
    output_frame_filename = fullfile(decompressed_folder, sprintf('frame_%03d.jpg', frame_idx));
    imwrite(reconstructed_frame_uint8, output_frame_filename, 'jpg', 'Quality', 95); % Save as JPG
    
    % Store for next P-frame (must be the same double-precision, clipped values as used in encoder)
    previous_reconstructed_frame_double = max(0, min(255, reconstructed_frame_double)); % Store the clipped double version

end % End frame loop

fclose(fid);
fprintf('Decompression finished. Output frames in: %s\n', decompressed_folder);