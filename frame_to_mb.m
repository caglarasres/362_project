% Given a frame (H, W, c)
% Convert it into macroblock representation
% returns a structure cell{mb_i, mb_j} = arr(8, 8, 3)
function mb_cells = frame_to_mb(frame)
    [H, W, c] = size(frame);
    mb_h = H / 8;
    mb_w = W / 8;
    mb_cells = cell(mb_h, mb_w);
    for i = 1:mb_h
        for j = 1:mb_w
            pos_i = (i-1)*8 + 1;
            pos_j = (j-1)*8 + 1;
            mb_cells{i, j} = frame(pos_i:pos_i+7, pos_j:pos_j+7, :);
        end
    end
end