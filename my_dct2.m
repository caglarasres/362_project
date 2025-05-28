% my_dct2.m
function output_matrix = my_dct2(input_matrix)
    % Performs 2D DCT on an input_matrix (e.g., 8x8).
    % Uses the separability property: DCT_2D(X) = T * X * T'
    % where T is the 1D DCT matrix.

    [M, N_cols] = size(input_matrix); % M rows, N_cols columns
    if M ~= N_cols
        % For this project, blocks are square (8x8).
        % If non-square were needed, we'd need T_M and T_N_cols.
        error('Input matrix must be square for this simplified DCT2 implementation.');
    end
    
    N = M; % Size of the square block (e.g., 8)

    % Use persistent variable to cache the DCT matrix to avoid recomputing it
    % for every block, as it's always the same for a given N.
    persistent dct_T_cached;
    persistent N_cached;

    if isempty(dct_T_cached) || isempty(N_cached) || N_cached ~= N
        dct_T_cached = my_dct_matrix(N);
        N_cached = N;
        % fprintf('Computed DCT matrix for N=%d\n', N); % For debugging
    end
    
    % Apply 2D DCT: Output = T * Input * T'
    output_matrix = dct_T_cached * input_matrix * dct_T_cached';
end