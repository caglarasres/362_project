function output_matrix = inverse_zigzag_scan(input_vector)
    % Converts a 1x64 vector back into an 8x8 matrix using inverse zigzag.
    output_matrix = zeros(8, 8);
    count = 1;
    for i = 1:15 % Max sum of indices
        if mod(i, 2) == 1 % Odd sum: Traverse upwards
            for r = i:-1:1
                c = i - r + 1;
                if r <= 8 && c <= 8
                    output_matrix(r, c) = input_vector(count);
                    count = count + 1;
                end
            end
        else % Even sum: Traverse downwards
            for c = i:-1:1
                r = i - c + 1;
                if r <= 8 && c <= 8
                    output_matrix(r, c) = input_vector(count);
                    count = count + 1;
                end
            end
        end
        if count > 64
            break;
        end
    end
end