% my_dct_matrix.m
function T = my_dct_matrix(N)
    % Creates an N x N DCT-II matrix.
    % This matrix T can be used for 1D DCT as Y = T * X (for column vector X)
    % or for 2D DCT as Y = T * X * T'
    % T(k+1, n+1) where k is frequency index (0 to N-1), n is time/space index (0 to N-1)
    
    T = zeros(N, N);
    for k = 0:N-1 % Frequency index
        if k == 0
            alpha_k = sqrt(1/N);
        else
            alpha_k = sqrt(2/N);
        end
        for n = 0:N-1 % Time/space index
            T(k+1, n+1) = alpha_k * cos(pi * (2*n + 1) * k / (2*N));
        end
    end
end

% % --- You can use this to test the DCT/IDCT pair ---
% N_test = 8;
% test_block_orig = rand(N_test, N_test) * 255; % Simulate an image block
% 
% T_dct = my_dct_matrix(N_test);
% 
% % 2D DCT: Y = T * X * T'
% dct_coeffs_custom = T_dct * test_block_orig * T_dct';
% 
% % 2D IDCT: X = T' * Y * T
% reconstructed_block_custom = T_dct' * dct_coeffs_custom * T_dct;
% 
% diff_custom = max(abs(test_block_orig(:) - reconstructed_block_custom(:)));
% fprintf('Max absolute difference (custom DCT/IDCT for a random block): %e\n', diff_custom);
% % This difference should be very small (e.g., 1e-12 or less)