function output_vector = run_length_decode(rle_input, expected_length)
    % Decodes Run-Length Encoded data.
    % rle_input format: [run1, val1; run2, val2; ...]
    output_vector = zeros(1, expected_length);
    currentIndex = 1;
    
    if isempty(rle_input)
        return; % Return zeros if rle_input is empty
    end

    for k = 1:size(rle_input, 1)
        run_length = rle_input(k, 1);
        value = rle_input(k, 2);
        
        if value == 0 % This was a run of zeros
            for j = 1:run_length
                if currentIndex <= expected_length
                    output_vector(currentIndex) = 0;
                    currentIndex = currentIndex + 1;
                else
                    % warning('RLE decode exceeded expected length for zero run.');
                    break;
                end
            end
        else % This was a non-zero value (run_length should be 1)
             if currentIndex <= expected_length
                output_vector(currentIndex) = value;
                currentIndex = currentIndex + 1;
             else
                % warning('RLE decode exceeded expected length for non-zero value.');
                break;
             end
        end
        if currentIndex > expected_length
            break;
        end
    end
    % If currentIndex < expected_length, the rest are zeros implicitly
    % This can happen if the RLE encoding stops early for trailing zeros
    % and no EOB marker is used to signify the end of 64 coefficients.
    % Our current RLE should always produce enough info to fill 64.
end