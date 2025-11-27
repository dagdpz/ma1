function [out] = ma1_analyze_reaches_by_hemifield(filepath)
% Analyze instructed and choice reaches to right and left hemifield with each hand
% Usage: analyze_reaches_by_hemifield('E:\Dropbox\DAG\Maria\20251007\Fen2025-10-07_01.mat')
% Created by Cursor AI, with loops

if nargin < 1
    filepath = 'E:\Dropbox\DAG\Maria\20251007\Fen2025-10-07_01.mat';
end

fprintf('\n=== LOADING DATA ===\n');
fprintf('File: %s\n', filepath);
data = load(filepath);
trials = data.trial;

fprintf('Total trials: %d\n', length(trials));

% Initialize counters for all combinations
stats = struct();
stats.instructed_left_hand_left = 0;
stats.instructed_left_hand_right = 0;
stats.instructed_right_hand_left = 0;
stats.instructed_right_hand_right = 0;
stats.choice_left_hand_left = 0;
stats.choice_left_hand_right = 0;
stats.choice_right_hand_left = 0;
stats.choice_right_hand_right = 0;

% Store trial indices for detailed analysis
indices = struct();
indices.instructed_left_hand_left = [];
indices.instructed_left_hand_right = [];
indices.instructed_right_hand_left = [];
indices.instructed_right_hand_right = [];
indices.choice_left_hand_left = [];
indices.choice_left_hand_right = [];
indices.choice_right_hand_left = [];
indices.choice_right_hand_right = [];

fprintf('\n=== ANALYZING TRIALS ===\n');

% Analyze each trial
for i = 1:length(trials)
    trial = trials(i);
    
    % Only analyze successful hand reaches
    if trial.effector ~= 1 || ~trial.success
        continue;
    end
    
    % Determine if instructed or choice
    is_choice = trial.choice;
    
    % Determine which hand was used
    hand_used = [];
    if isfield(trial, 'reach_hand')
        hand_used = trial.reach_hand; % 1=left hand, 2=right hand
    elseif isfield(trial, 'hand')
        hand_used = trial.hand;
    end
    
    % Determine target hemifield (from target position)
    target_hemifield = [];
    if isfield(trial, 'target_selected') && length(trial.target_selected) >= 2
        target_idx = trial.target_selected(2);
        
        % Get target position from hnd.tar structure
        if isfield(trial, 'hnd') && isfield(trial.hnd, 'tar') && length(trial.hnd.tar) >= target_idx
            if isfield(trial.hnd.tar(target_idx), 'x')
                target_x = trial.hnd.tar(target_idx).x;
                if target_x < 0
                    target_hemifield = 1; % left hemifield
                else
                    target_hemifield = 2; % right hemifield
                end
            end
        end
    end
    
    % Skip if we couldn't determine hand or hemifield
    if isempty(hand_used) || isempty(target_hemifield)
        continue;
    end
    
    % Categorize the reach
    if ~is_choice % instructed
        if hand_used == 1 % left hand
            if target_hemifield == 1 % left hemifield
                stats.instructed_left_hand_left = stats.instructed_left_hand_left + 1;
                indices.instructed_left_hand_left(end+1) = i;
            else % right hemifield
                stats.instructed_left_hand_right = stats.instructed_left_hand_right + 1;
                indices.instructed_left_hand_right(end+1) = i;
            end
        else % right hand
            if target_hemifield == 1 % left hemifield
                stats.instructed_right_hand_left = stats.instructed_right_hand_left + 1;
                indices.instructed_right_hand_left(end+1) = i;
            else % right hemifield
                stats.instructed_right_hand_right = stats.instructed_right_hand_right + 1;
                indices.instructed_right_hand_right(end+1) = i;
            end
        end
    else % choice
        if hand_used == 1 % left hand
            if target_hemifield == 1 % left hemifield
                stats.choice_left_hand_left = stats.choice_left_hand_left + 1;
                indices.choice_left_hand_left(end+1) = i;
            else % right hemifield
                stats.choice_left_hand_right = stats.choice_left_hand_right + 1;
                indices.choice_left_hand_right(end+1) = i;
            end
        else % right hand
            if target_hemifield == 1 % left hemifield
                stats.choice_right_hand_left = stats.choice_right_hand_left + 1;
                indices.choice_right_hand_left(end+1) = i;
            else % right hemifield
                stats.choice_right_hand_right = stats.choice_right_hand_right + 1;
                indices.choice_right_hand_right(end+1) = i;
            end
        end
    end
end

% Display statistics
fprintf('\n');
fprintf('╔═══════════════════════════════════════════════════════════════╗\n');
fprintf('║                    INSTRUCTED REACHES                         ║\n');
fprintf('╠═══════════════════════════════════════════════════════════════╣\n');
fprintf('║                 │   Left Hemifield  │  Right Hemifield        ║\n');
fprintf('╠═════════════════╪═══════════════════╪═════════════════════════╣\n');
fprintf('║   Left Hand     │       %3d         │       %3d               ║\n', ...
    stats.instructed_left_hand_left, stats.instructed_left_hand_right);
fprintf('║   Right Hand    │       %3d         │       %3d               ║\n', ...
    stats.instructed_right_hand_left, stats.instructed_right_hand_right);
fprintf('╠═════════════════╪═══════════════════╪═════════════════════════╣\n');
fprintf('║   Total         │       %3d         │       %3d               ║\n', ...
    stats.instructed_left_hand_left + stats.instructed_right_hand_left, ...
    stats.instructed_left_hand_right + stats.instructed_right_hand_right);
fprintf('╚═══════════════════════════════════════════════════════════════╝\n');

fprintf('\n');
fprintf('╔═══════════════════════════════════════════════════════════════╗\n');
fprintf('║                       CHOICE REACHES                          ║\n');
fprintf('╠═══════════════════════════════════════════════════════════════╣\n');
fprintf('║                 │   Left Hemifield  │  Right Hemifield        ║\n');
fprintf('╠═════════════════╪═══════════════════╪═════════════════════════╣\n');
fprintf('║   Left Hand     │       %3d         │       %3d               ║\n', ...
    stats.choice_left_hand_left, stats.choice_left_hand_right);
fprintf('║   Right Hand    │       %3d         │       %3d               ║\n', ...
    stats.choice_right_hand_left, stats.choice_right_hand_right);
fprintf('╠═════════════════╪═══════════════════╪═════════════════════════╣\n');
fprintf('║   Total         │       %3d         │       %3d               ║\n', ...
    stats.choice_left_hand_left + stats.choice_right_hand_left, ...
    stats.choice_left_hand_right + stats.choice_right_hand_right);
fprintf('╚═══════════════════════════════════════════════════════════════╝\n');

% Calculate totals
total_instructed = stats.instructed_left_hand_left + stats.instructed_left_hand_right + ...
                   stats.instructed_right_hand_left + stats.instructed_right_hand_right;
total_choice = stats.choice_left_hand_left + stats.choice_left_hand_right + ...
               stats.choice_right_hand_left + stats.choice_right_hand_right;

fprintf('\n=== SUMMARY ===\n');
fprintf('Total Instructed Reaches: %d\n', total_instructed);
fprintf('Total Choice Reaches: %d\n', total_choice);
fprintf('Total Analyzed Reaches: %d\n', total_instructed + total_choice);

% Create visualization
create_visualization(stats, filepath);

% Return stats and indices
assignin('base', 'reach_stats', stats);
assignin('base', 'reach_indices', indices);
fprintf('\nVariables ''reach_stats'' and ''reach_indices'' saved to workspace.\n');

end

function create_visualization(stats, filepath)
    figure('Position', [100, 100, 1400, 600], 'Name', 'Reach Analysis by Hemifield');
    
    % Instructed reaches
    subplot(2,3,1);
    instructed_data = [stats.instructed_left_hand_left, stats.instructed_left_hand_right; ...
                       stats.instructed_right_hand_left, stats.instructed_right_hand_right];
    b = bar(instructed_data, 'grouped');
    b(1).FaceColor = [0.2 0.4 0.8]; % blue for left hemifield
    b(2).FaceColor = [0.8 0.4 0.2]; % orange for right hemifield
    set(gca, 'XTickLabel', {'Left Hand', 'Right Hand'});
    ylabel('Number of Reaches');
    title('Instructed Reaches', 'FontWeight', 'bold');
    legend('Left Hemifield', 'Right Hemifield', 'Location', 'best');
    grid on;
    
    % Choice reaches
    subplot(2,3,2);
    choice_data = [stats.choice_left_hand_left, stats.choice_left_hand_right; ...
                   stats.choice_right_hand_left, stats.choice_right_hand_right];
    b = bar(choice_data, 'grouped');
    b(1).FaceColor = [0.2 0.4 0.8];
    b(2).FaceColor = [0.8 0.4 0.2];
    set(gca, 'XTickLabel', {'Left Hand', 'Right Hand'});
    ylabel('Number of Reaches');
    title('Choice Reaches', 'FontWeight', 'bold');
    legend('Left Hemifield', 'Right Hemifield', 'Location', 'best');
    grid on;
    
    % Combined comparison
    subplot(2,3,3);
    combined = [sum(instructed_data(:,1)), sum(instructed_data(:,2)); ...
                sum(choice_data(:,1)), sum(choice_data(:,2))];
    b = bar(combined, 'grouped');
    b(1).FaceColor = [0.2 0.4 0.8];
    b(2).FaceColor = [0.8 0.4 0.2];
    set(gca, 'XTickLabel', {'Instructed', 'Choice'});
    ylabel('Number of Reaches');
    title('Total by Type', 'FontWeight', 'bold');
    legend('Left Hemifield', 'Right Hemifield', 'Location', 'best');
    grid on;
    
    % Heatmap for instructed
    subplot(2,3,4);
    imagesc(instructed_data);
    colorbar;
    set(gca, 'XTickLabel', {'Left Hem.', 'Right Hem.'}, 'XTick', 1:2);
    set(gca, 'YTickLabel', {'Left Hand', 'Right Hand'}, 'YTick', 1:2);
    title('Instructed (Heatmap)', 'FontWeight', 'bold');
    colormap(gca, hot);
    % Add text annotations
    for i = 1:2
        for j = 1:2
            text(j, i, num2str(instructed_data(i,j)), ...
                'HorizontalAlignment', 'center', 'Color', 'white', 'FontWeight', 'bold');
        end
    end
    
    % Heatmap for choice
    subplot(2,3,5);
    imagesc(choice_data);
    colorbar;
    set(gca, 'XTickLabel', {'Left Hem.', 'Right Hem.'}, 'XTick', 1:2);
    set(gca, 'YTickLabel', {'Left Hand', 'Right Hand'}, 'YTick', 1:2);
    title('Choice (Heatmap)', 'FontWeight', 'bold');
    colormap(gca, hot);
    % Add text annotations
    for i = 1:2
        for j = 1:2
            text(j, i, num2str(choice_data(i,j)), ...
                'HorizontalAlignment', 'center', 'Color', 'white', 'FontWeight', 'bold');
        end
    end
    
    % Summary text
    subplot(2,3,6);
    axis off;
    
    total_inst = sum(instructed_data(:));
    total_ch = sum(choice_data(:));
    
    summary_text = {
        sprintf('SUMMARY STATISTICS'),
        sprintf(''),
        sprintf('INSTRUCTED:'),
        sprintf('  Left Hand → Left Hem: %d', stats.instructed_left_hand_left),
        sprintf('  Left Hand → Right Hem: %d', stats.instructed_left_hand_right),
        sprintf('  Right Hand → Left Hem: %d', stats.instructed_right_hand_left),
        sprintf('  Right Hand → Right Hem: %d', stats.instructed_right_hand_right),
        sprintf('  Total: %d', total_inst),
        sprintf(''),
        sprintf('CHOICE:'),
        sprintf('  Left Hand → Left Hem: %d', stats.choice_left_hand_left),
        sprintf('  Left Hand → Right Hem: %d', stats.choice_left_hand_right),
        sprintf('  Right Hand → Left Hem: %d', stats.choice_right_hand_left),
        sprintf('  Right Hand → Right Hem: %d', stats.choice_right_hand_right),
        sprintf('  Total: %d', total_ch),
        sprintf(''),
        sprintf('GRAND TOTAL: %d reaches', total_inst + total_ch)
    };
    
    text(0.1, 0.95, summary_text, 'VerticalAlignment', 'top', ...
         'FontName', 'Courier', 'FontSize', 9, 'FontWeight', 'bold');
    
    [~, filename, ext] = fileparts(filepath);
    sgtitle(sprintf('Reach Analysis: %s%s', filename, ext), ...
            'FontSize', 14, 'FontWeight', 'bold');
end

