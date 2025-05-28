% my_idct2.m
function output_matrix = my_idct2(input_matrix_dct_coeffs)
    % Performs 2D Inverse DCT on an input_matrix of DCT coefficients.
    % Uses the separability property: IDCT_2D(Y) = T' * Y * T
    % where T is the 1D DCT matrix, and T' is its transpose.

    [M, N_cols] = size(input_matrix_dct_coeffs);
    if M ~= N_cols
        error('Input matrix must be square for this simplified IDCT2 implementation.');
    end

    N = M;

    persistent idct_T_transpose_cached;
    persistent idct_T_cached; % Need T itself for T_transpose * Y * T
    persistent N_idct_cached;

    if isempty(idct_T_transpose_cached) || isempty(N_idct_cached) || N_idct_cached ~= N
        temp_T = my_dct_matrix(N);
        idct_T_transpose_cached = temp_T';
        idct_T_cached = temp_T; % Store T itself
        N_idct_cached = N;
        % fprintf('Computed IDCT matrices for N=%d\n', N); % For debugging
    end
    
    % Apply 2D IDCT: Output = T' * Input_DCT_Coeffs * T
    output_matrix = idct_T_transpose_cached * input_matrix_dct_coeffs * idct_T_cached;
end