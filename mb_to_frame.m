function frame = mb_to_frame(mb_cells)
    [mb_h, mb_w] = size(mb_cells);
    frame = zeros(mb_h*8, mb_w*8, 3);

    for i = 1:mb_h
        for j = 1:mb_w
            pos_i = (i-1)*8 + 1;
            pos_j = (j-1)*8 + 1;
            frame(pos_i:pos_i+7, pos_j:pos_j+7, :) = mb_cells{i, j};
        end
    end  
end
