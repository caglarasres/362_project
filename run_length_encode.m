function rle_output = run_length_encode(input_vector)
    % Performs Run-Length Encoding.
    % Output format: [run1, val1; run2, val2; ...]
    % Special handling for zeros: (run_length_of_zeros, 0)
    % Non-zeros are (1, value)
    
    if isempty(input_vector)
        rle_output = [];
        return;
    end

    rle_output = [];
    i = 1;
    n = length(input_vector);
    
    while i <= n
        val = input_vector(i);
        if val == 0
            count = 0;
            while i <= n && input_vector(i) == 0
                count = count + 1;
                i = i + 1;
            end
            rle_output = [rle_output; count, 0];
        else % Non-zero value
            rle_output = [rle_output; 1, val];
            i = i + 1;
        end
    end
    % Add an End-Of-Block (EOB) marker, (0,0) is often used, 
    % or a special pair like (-1,-1) if 0,0 can be valid data
    % For this simplified version, we can just rely on knowing we always have 64 coeffs.
    % However, standard RLE might use an EOB if the tail is all zeros.
    % Let's make it simple: if the last run was zeros and covered till the end, it's fine.
    % If not, and we need to fill up to 64, this RLE is lossy if not handled by EOB.
    % The project implies we RLE the 64 coefficients.
    % If the last elements are non-zero, they are [1, val]. If they are zero, they are [count, 0].
end