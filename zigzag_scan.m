function output_vector = zigzag_scan(input_matrix)
    % Converts an 8x8 matrix into a 1x64 vector using zigzag scanning.
    output_vector = zeros(1, 64);
    count = 1;
    for i = 1:15 % Max sum of indices is 8+8-1 = 15 (1-based)
        if mod(i, 2) == 1 % Odd sum: Traverse upwards
            for r = i:-1:1
                c = i - r + 1;
                if r <= 8 && c <= 8
                    output_vector(count) = input_matrix(r, c);
                    count = count + 1;
                end
            end
        else % Even sum: Traverse downwards
            for c = i:-1:1
                r = i - c + 1;
                if r <= 8 && c <= 8
                    output_vector(count) = input_matrix(r, c);
                    count = count + 1;
                end
            end
        end
    end
end