function [left_reaches, right_reaches, details] = ma1_reaches_analyze(filepath)
    % REACHES HAND AND TARGET SELECTION ANALYSIS
    
    fprintf('=== COMPLETE REACHES HAND AND TARGET SELECTION ANALYSIS ===\n');
    
   
    data = load(filepath);
    trials = data.trial;
    
    fprintf('Total trials in dataset: %d\n', length(trials));
    
 
    idx_success = find([trials.success] == 1);
    idx_failed = find([trials.success] == 0);
    fprintf('Successful trials: %d\n', length(idx_success));
    fprintf('Failed trials: %d\n', length(idx_failed));
    
    % Ensure indices are within bounds for reach_hand data
    if isfield(trials, 'reach_hand')
        reach_hands_all = [trials.reach_hand];
        fprintf('Total reach_hand data points: %d\n', length(reach_hands_all));
        
        % All trials
        valid_trial_idx = 1:length(trials);
        valid_trial_idx = valid_trial_idx(valid_trial_idx <= length(reach_hands_all));
    else
        valid_trial_idx = 1:length(trials);
        reach_hands_all = [];
    end
    
    % Сhoice field
    has_choice_field = isfield(trials, 'choice');
    if has_choice_field
        idx_free = find([trials.choice] == 1);
        idx_instructed = find([trials.choice] == 0);
        idx_free_success = intersect(idx_free, idx_success);
        idx_instructed_success = intersect(idx_instructed, idx_success);
        
        % ANALYSIS OF REACH_HAND FOR EACH TASK TYPE (ALL AND SUCCESS ONLY)
        fprintf('\n=== REACH_HAND DISTRIBUTION BY TASK TYPE ===\n');
        
        % Free choice trials - ALL
        if ~isempty(idx_free) && ~isempty(reach_hands_all)
            % Filter indices to only those within reach_hands_all bounds
            idx_free_valid = idx_free(idx_free <= length(reach_hands_all));
            if ~isempty(idx_free_valid)
                free_reach_hands = reach_hands_all(idx_free_valid);
                free_left = sum(free_reach_hands == 1);
                free_right = sum(free_reach_hands == 2);
                free_total = free_left + free_right;
                
                fprintf('FREE CHOICE trials (ALL):\n');
                fprintf('  Total trials: %d\n', length(idx_free));
                %fprintf('  Trials with reach_hand data: %d\n', length(idx_free_valid));
                fprintf('  Left hand: %d (%.1f%%)\n', free_left, (free_left/free_total)*100);
                fprintf('  Right hand: %d (%.1f%%)\n', free_right, (free_right/free_total)*100);
            else
                fprintf('FREE CHOICE trials (ALL): No valid reach_hand data\n');
            end
        else
            fprintf('FREE CHOICE trials (ALL): No data available\n');
        end
        
        % Free choice trials - SUCCESS ONLY
        if ~isempty(idx_free_success) && ~isempty(reach_hands_all)
            % Filter indices to only those within reach_hands_all bounds
            idx_free_success_valid = idx_free_success(idx_free_success <= length(reach_hands_all));
            if ~isempty(idx_free_success_valid)
                free_success_reach_hands = reach_hands_all(idx_free_success_valid);
                free_success_left = sum(free_success_reach_hands == 1);
                free_success_right = sum(free_success_reach_hands == 2);
                free_success_total = free_success_left + free_success_right;
                
                fprintf('FREE CHOICE trials (SUCCESS ONLY):\n');
                fprintf('  Total successful trials: %d\n', length(idx_free_success));
                %fprintf('  Trials with reach_hand data: %d\n', length(idx_free_success_valid));
                fprintf('  Left hand: %d (%.1f%%)\n', free_success_left, (free_success_left/free_success_total)*100);
                fprintf('  Right hand: %d (%.1f%%)\n', free_success_right, (free_success_right/free_success_total)*100);
            else
                fprintf('FREE CHOICE trials (SUCCESS ONLY): No valid reach_hand data\n');
            end
        else
            fprintf('FREE CHOICE trials (SUCCESS ONLY): No data available\n');
        end
        
        % Instructed trials - ALL
        if ~isempty(idx_instructed) && ~isempty(reach_hands_all)
            % Filter indices to only those within reach_hands_all bounds
            idx_instructed_valid = idx_instructed(idx_instructed <= length(reach_hands_all));
            if ~isempty(idx_instructed_valid)
                instructed_reach_hands = reach_hands_all(idx_instructed_valid);
                instructed_left = sum(instructed_reach_hands == 1);
                instructed_right = sum(instructed_reach_hands == 2);
                instructed_total = instructed_left + instructed_right;
                
                fprintf('INSTRUCTED trials (ALL):\n');
                fprintf('  Total trials: %d\n', length(idx_instructed));
                %fprintf('  Trials with reach_hand data: %d\n', length(idx_instructed_valid));
                fprintf('  Left hand: %d (%.1f%%)\n', instructed_left, (instructed_left/instructed_total)*100);
                fprintf('  Right hand: %d (%.1f%%)\n', instructed_right, (instructed_right/instructed_total)*100);
            else
                fprintf('INSTRUCTED trials (ALL): No valid reach_hand data\n');
            end
        else
            fprintf('INSTRUCTED trials (ALL): No data available\n');
        end
        
        % Instructed trials - SUCCESS ONLY
        if ~isempty(idx_instructed_success) && ~isempty(reach_hands_all)
            % Filter indices to only those within reach_hands_all bounds
            idx_instructed_success_valid = idx_instructed_success(idx_instructed_success <= length(reach_hands_all));
            if ~isempty(idx_instructed_success_valid)
                instructed_success_reach_hands = reach_hands_all(idx_instructed_success_valid);
                instructed_success_left = sum(instructed_success_reach_hands == 1);
                instructed_success_right = sum(instructed_success_reach_hands == 2);
                instructed_success_total = instructed_success_left + instructed_success_right;
                
                fprintf('INSTRUCTED trials (SUCCESS ONLY):\n');
                fprintf('  Total successful trials: %d\n', length(idx_instructed_success));
                %fprintf('  Trials with reach_hand data: %d\n', length(idx_instructed_success_valid));
                fprintf('  Left hand: %d (%.1f%%)\n', instructed_success_left, (instructed_success_left/instructed_success_total)*100);
                fprintf('  Right hand: %d (%.1f%%)\n', instructed_success_right, (instructed_success_right/instructed_success_total)*100);
            else
                fprintf('INSTRUCTED trials (SUCCESS ONLY): No valid reach_hand data\n');
            end
        else
            fprintf('INSTRUCTED trials (SUCCESS ONLY): No data available\n');
        end
        
        fprintf('Free choice successful trials: %d\n', length(idx_free_success));
        fprintf('Instructed successful trials: %d\n', length(idx_instructed_success));
    else
        idx_free_success = [];
        idx_instructed_success = [];
        fprintf('No choice field found - skipping task type analysis\n');
    end
    
    % ANALYSIS 1: REACH_HAND ANALYSIS FOR ALL TRIALS
    fprintf('\n=== REACH_HAND ANALYSIS ===\n');
    
    if isfield(trials, 'reach_hand') && ~isempty(valid_trial_idx)
        reach_hands_all_valid = reach_hands_all(valid_trial_idx);
        
        left_hand_all = sum(reach_hands_all_valid == 1);
        right_hand_all = sum(reach_hands_all_valid == 2);
        other_hand_all = sum(~ismember(reach_hands_all_valid, [1, 2]));
        total_with_hand = left_hand_all + right_hand_all + other_hand_all;
        
        fprintf('Total trials with reach_hand: %d\n', total_with_hand);
        fprintf('Left hand: %d (%.1f%%)\n', left_hand_all, (left_hand_all/total_with_hand)*100);
        fprintf('Right hand: %d (%.1f%%)\n', right_hand_all, (right_hand_all/total_with_hand)*100);
        
        if other_hand_all > 0
            other_values = unique(reach_hands_all_valid(~ismember(reach_hands_all_valid, [1, 2])));
            fprintf('Other hand values: %s\n', mat2str(other_values));
        end
        
    else
        fprintf('No reach_hand data available\n');
        left_hand_all = 0;
        right_hand_all = 0;
        reach_hands_all_valid = [];
    end
    
    % ANALYSIS 2: TARGET POSITION ANALYSIS USING LAST NON-NAN X_HND VALUES
    fprintf('\n=== TARGET POSITION ANALYSIS (USING LAST NON-NAN X_HND) ===\n');

    target_values = [];
    target_positions = [];
    left_targets_all = 0;
    right_targets_all = 0;
    
    % Extract target data from last non-NaN x_hnd values
    if ~isempty(valid_trial_idx)
        % Initialize arrays for all trials
        target_values = NaN(1, length(valid_trial_idx));
        target_positions = NaN(1, length(valid_trial_idx));
        
        for i = 1:length(valid_trial_idx)
            trial_idx = valid_trial_idx(i);
            
            % METHOD: Use last non-NaN value from x_hnd
            if isfield(trials(trial_idx), 'x_hnd') && ~isempty(trials(trial_idx).x_hnd)
                x_hnd_data = trials(trial_idx).x_hnd;
                
                % Find last non-NaN value
                non_nan_indices = find(~isnan(x_hnd_data));
                
                if ~isempty(non_nan_indices)
                    last_non_nan_idx = non_nan_indices(end);
                    final_x_value = x_hnd_data(last_non_nan_idx);
                    
                    target_positions(i) = final_x_value;
                    target_values(i) = classify_target_position(final_x_value);
                    
                    % Debug output for first few trials
                    if i <= 5
                        fprintf('Trial %d: last non-NaN x_hnd = %.3f (target: %d)\n', ...
                            trial_idx, final_x_value, target_values(i));
                    end
                else
                    % All values are NaN
                    target_positions(i) = NaN;
                    target_values(i) = NaN;
                end
            else
                % No x_hnd data
                target_positions(i) = NaN;
                target_values(i) = NaN;
            end
        end
        
        % Count results for all trials
        if ~isempty(target_values)
            valid_targets = ~isnan(target_values);
            left_targets_all = sum(target_values(valid_targets) == 1);
            right_targets_all = sum(target_values(valid_targets) == 2);
            
            fprintf('Total trials with target data: %d\n', sum(valid_targets));
            fprintf('Left targets: %d\n', left_targets_all);
            fprintf('Right targets: %d\n', right_targets_all);
            
            if sum(valid_targets) > 0
                fprintf('Target distribution: %.1f%% left, %.1f%% right\n', ...
                    (left_targets_all/sum(valid_targets))*100, (right_targets_all/sum(valid_targets))*100);
            end
        end
    end
    
    % ANALYSIS 3: HAND-TARGET COMBINATIONS (ONLY SUCCESSFUL TRIALS)
    fprintf('\n=== HAND-TARGET COMBINATION ANALYSIS (SUCCESSFUL ONLY) ===\n');
    
    free_LL = 0; free_LR = 0; free_RL = 0; free_RR = 0;
    instructed_LL = 0; instructed_LR = 0; instructed_RL = 0; instructed_RR = 0;
    
    % Percentages for successful trials
    free_success_count = length(idx_free_success);
    instructed_success_count = length(idx_instructed_success);
    total_success_count = length(idx_success);
    
    if total_success_count > 0
        free_percentage = (free_success_count / total_success_count) * 100;
        instructed_percentage = (instructed_success_count / total_success_count) * 100;
    else
        free_percentage = 0;
        instructed_percentage = 0;
    end
    
    % For combination analysis we use only successful trials!!
    if has_choice_field && ~isempty(idx_success) && ~isempty(target_values) && ~isempty(reach_hands_all) && any(~isnan(target_values))
        
        % Successful trials data
        success_positions = ismember(valid_trial_idx, idx_success);
        reach_hands_success = reach_hands_all(success_positions);
        target_values_success = target_values(success_positions);
        
        % FREE CHOICE TRIALS
        if ~isempty(idx_free_success)
            free_positions = ismember(valid_trial_idx, idx_free_success);
            free_hands = reach_hands_all(free_positions);
            free_targets = target_values(free_positions);
            
            valid_free = (free_targets == 1 | free_targets == 2) & (free_hands == 1 | free_hands == 2);
            free_hands_valid = free_hands(valid_free);
            free_targets_valid = free_targets(valid_free);
            
            if ~isempty(free_hands_valid)
                free_LL = sum(free_hands_valid == 1 & free_targets_valid == 1);
                free_LR = sum(free_hands_valid == 1 & free_targets_valid == 2);
                free_RL = sum(free_hands_valid == 2 & free_targets_valid == 1);
                free_RR = sum(free_hands_valid == 2 & free_targets_valid == 2);
                
                fprintf('\n=== FREE CHOICE SUCCESSFUL TRIALS ===\n');
                %fprintf('Total with valid hand-target data: %d\n', length(free_hands_valid));
                fprintf('Left Hand - Left Target: %d\n', free_LL);
                fprintf('Left Hand - Right Target: %d\n', free_LR);
                fprintf('Right Hand - Left Target: %d\n', free_RL);
                fprintf('Right Hand - Right Target: %d\n', free_RR);
            end
        end
        
        % INSTRUCTED TRIALS
        if ~isempty(idx_instructed_success)
            instructed_positions = ismember(valid_trial_idx, idx_instructed_success);
            instructed_hands = reach_hands_all(instructed_positions);
            instructed_targets = target_values(instructed_positions);
            
            valid_instructed = (instructed_targets == 1 | instructed_targets == 2) & (instructed_hands == 1 | instructed_hands == 2);
            instructed_hands_valid = instructed_hands(valid_instructed);
            instructed_targets_valid = instructed_targets(valid_instructed);
            
            if ~isempty(instructed_hands_valid)
                instructed_LL = sum(instructed_hands_valid == 1 & instructed_targets_valid == 1);
                instructed_LR = sum(instructed_hands_valid == 1 & instructed_targets_valid == 2);
                instructed_RL = sum(instructed_hands_valid == 2 & instructed_targets_valid == 1);
                instructed_RR = sum(instructed_hands_valid == 2 & instructed_targets_valid == 2);
                
                fprintf('\n=== INSTRUCTED SUCCESSFUL TRIALS ===\n');
                %fprintf('Total with valid hand-target data: %d\n', length(instructed_hands_valid));
                fprintf('Left Hand - Left Target: %d\n', instructed_LL);
                fprintf('Left Hand - Right Target: %d\n', instructed_LR);
                fprintf('Right Hand - Left Target: %d\n', instructed_RL);
                fprintf('Right Hand - Right Target: %d\n', instructed_RR);
            end
        end
    end
    
    % CREATE SUMMARY TABLE FOR ALL TRIALS
    create_summary_table(trials, valid_trial_idx, has_choice_field, target_positions, target_values, filepath);
    
    % CREATE ALL PLOTS
    if has_choice_field
        create_all_plots(free_LL, free_LR, free_RL, free_RR, instructed_LL, instructed_LR, instructed_RL, instructed_RR, ...
                        free_success_count, free_percentage, instructed_success_count, instructed_percentage, ...
                        total_success_count, filepath);
    end
    
    % FINAL SUCCESS SUMMARY
    fprintf('\n=== FINAL SUCCESS SUMMARY ===\n');
    fprintf('Total trials: %d\n', length(trials));
    fprintf('Successful trials: %d (%.1f%%)\n', length(idx_success), (length(idx_success)/length(trials))*100);
    fprintf('Failed trials: %d (%.1f%%)\n', length(idx_failed), (length(idx_failed)/length(trials))*100);
    
    if has_choice_field
        fprintf('Free choice successful: %d\n', length(idx_free_success));
        fprintf('Instructed successful: %d\n', length(idx_instructed_success));
    end
    
    fprintf('Left hand reaches: %d\n', left_hand_all);
    fprintf('Right hand reaches: %d\n', right_hand_all);
    
    if ~isempty(target_values)
        valid_targets = sum(~isnan(target_values));
        fprintf('Trials with target data: %d\n', valid_targets);
        if valid_targets > 0
            fprintf('Left targets: %d (%.1f%%)\n', left_targets_all, (left_targets_all/valid_targets)*100);
            fprintf('Right targets: %d (%.1f%%)\n', right_targets_all, (right_targets_all/valid_targets)*100);
        end
    end
    
    % HAND-TARGET COMBINATION SUMMARY
    if has_choice_field
        fprintf('\n--- HAND-TARGET COMBINATIONS (SUCCESSFUL ONLY) ---\n');
        
        if (free_LL + free_LR + free_RL + free_RR) > 0
            fprintf('FREE CHOICE:\n');
            fprintf('  LL: %d, LR: %d, RL: %d, RR: %d\n', free_LL, free_LR, free_RL, free_RR);
            free_total = free_LL + free_LR + free_RL + free_RR;
            free_ipsi = free_LL + free_RR;
            free_contra = free_LR + free_RL;
            if free_total > 0
                fprintf('  Ipsilateral: %d/%d (%.1f%%)\n', free_ipsi, free_total, (free_ipsi/free_total)*100);
                fprintf('  Contralateral: %d/%d (%.1f%%)\n', free_contra, free_total, (free_contra/free_total)*100);
            end
        end
        
        if (instructed_LL + instructed_LR + instructed_RL + instructed_RR) > 0
            fprintf('INSTRUCTED:\n');
            fprintf('  LL: %d, LR: %d, RL: %d, RR: %d\n', instructed_LL, instructed_LR, instructed_RL, instructed_RR);
            instructed_total = instructed_LL + instructed_LR + instructed_RL + instructed_RR;
            instructed_ipsi = instructed_LL + instructed_RR;
            instructed_contra = instructed_LR + instructed_RL;
            if instructed_total > 0
                fprintf('  Ipsilateral: %d/%d (%.1f%%)\n', instructed_ipsi, instructed_total, (instructed_ipsi/instructed_total)*100);
                fprintf('  Contralateral: %d/%d (%.1f%%)\n', instructed_contra, instructed_total, (instructed_contra/instructed_total)*100);
            end
        end
    end
    
    fprintf('\n=== ANALYSIS COMPLETED SUCCESSFULLY ===\n');
    
    % Prepare outputs
    left_reaches = left_hand_all;
    right_reaches = right_hand_all;
    
    details.all_trials = length(trials);
    details.successful_trials = length(idx_success);
    details.failed_trials = length(idx_failed);
    details.valid_trials = length(valid_trial_idx);
    details.left_reaches = left_hand_all;
    details.right_reaches = right_hand_all;
    details.left_targets = left_targets_all;
    details.right_targets = right_targets_all;
    
    if has_choice_field
        details.free_combinations = [free_LL, free_LR, free_RL, free_RR];
        details.instructed_combinations = [instructed_LL, instructed_LR, instructed_RL, instructed_RR];
        details.free_success_count = free_success_count;
        details.instructed_success_count = instructed_success_count;
    end
end

% Helper function to classify target position based on x_hnd value
function target_code = classify_target_position(x_position)
    if x_position < 0
        target_code = 1; % Left target
    elseif x_position > 0
        target_code = 2; % Right target
    else
        target_code = NaN; % Center or undefined
    end
end

% Summary table
function create_summary_table(trials, valid_trial_idx, has_choice_field, target_positions, target_values, filepath)
    fprintf('Creating summary table for all trials...\n');
    
    % Data for table
    num_trials = length(valid_trial_idx);
    trial_numbers = zeros(num_trials, 1);
    task_types = cell(num_trials, 1);
    reach_hands = cell(num_trials, 1);
    target_choices = cell(num_trials, 1);
    coordinates = zeros(num_trials, 1);
    success_status = cell(num_trials, 1);
    
    for i = 1:num_trials
        trial_idx = valid_trial_idx(i);
        
        % Trial number
        trial_numbers(i) = trial_idx;
        
        % Task type
        if has_choice_field
            if trials(trial_idx).choice == 1
                task_types{i} = 'Free';
            else
                task_types{i} = 'Instructed';
            end
        else
            task_types{i} = 'Unknown';
        end
        
        % Reach hand
        if isfield(trials, 'reach_hand')
            hand_val = trials(trial_idx).reach_hand;
            if hand_val == 1
                reach_hands{i} = 'Left';
            elseif hand_val == 2
                reach_hands{i} = 'Right';
            else
                reach_hands{i} = num2str(hand_val);
            end
        else
            reach_hands{i} = 'No data';
        end
        
        % Target choice (left or right)
        if ~isnan(target_values(i))
            if target_values(i) == 1
                target_choices{i} = 'Left';
            elseif target_values(i) == 2
                target_choices{i} = 'Right';
            else
                target_choices{i} = 'Unknown';
            end
        else
            target_choices{i} = 'No data';
        end
        
        % Coordinates
        if ~isnan(target_positions(i))
            coordinates(i) = target_positions(i);
        else
            coordinates(i) = NaN;
        end
        
        % Success status (✓ for success, ✗ for failed)
        if trials(trial_idx).success == 1
            success_status{i} = '✓';
        else
            success_status{i} = '✗';
        end
    end
    
    % Create table
    summary_table = table(trial_numbers, task_types, reach_hands, target_choices, coordinates, success_status, ...
        'VariableNames', {'Trial', 'TaskType', 'ReachHand', 'TargetChoice', 'TargetX', 'Success'});
    
    % Display table 
    fig = figure('Position', [100, 100, 900, 600], 'Name', 'Complete Trial Summary Table');
    
    % Create uitable
    t = uitable(fig, 'Data', table2cell(summary_table), ...
        'ColumnName', {'Trial', 'Task Type', 'Reach Hand', 'Target Choice', 'Target X', 'Success'}, ...
        'ColumnWidth', {60, 80, 80, 80, 80, 60}, ...
        'Position', [20, 50, 860, 500], ...
        'RowName', []);
    
    % Add title
    [~, name, ext] = fileparts(filepath);
    uicontrol('Style', 'text', ...
        'String', sprintf('Complete Trial Summary - %s%s', name, ext), ...
        'Position', [20, 560, 860, 30], ...
        'FontSize', 14, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center');
    
    % Add statistics
    success_count = sum([trials.success] == 1);
    failed_count = sum([trials.success] == 0);
    stats_text = sprintf('Total trials: %d | Successful: %d (✓) | Failed: %d (✗)', ...
        length(trials), success_count, failed_count);
    uicontrol('Style', 'text', ...
        'String', stats_text, ...
        'Position', [20, 20, 860, 20], ...
        'FontSize', 10, ...
        'HorizontalAlignment', 'center');
    
    fprintf('Summary table created with %d trials (all trials)\n', num_trials);
end

% Plots
function create_all_plots(free_LL, free_LR, free_RL, free_RR, instructed_LL, instructed_LR, instructed_RL, instructed_RR, ...
                         free_success_count, free_percentage, instructed_success_count, instructed_percentage, ...
                         total_success_count, filepath)
    
    
    fig = figure('Position', [50, 50, 1400, 1000], 'Name', 'Comprehensive Analysis Results');
    
    % Plot 1: Hand-Target Combinations - Free Choice
    subplot(2, 2, 1);
    create_combination_plot(free_LL, free_LR, free_RL, free_RR, 'Free Choice', free_success_count, free_percentage);
    
    % Plot 2: Hand-Target Combinations - Instructed
    subplot(2, 2, 2);
    create_combination_plot(instructed_LL, instructed_LR, instructed_RL, instructed_RR, 'Instructed', instructed_success_count, instructed_percentage);
    
    % Plot 3: Ipsilateral vs Contralateral (Overall)
    subplot(2, 2, 3);
    create_ipsi_contra_plot(free_LL, free_LR, free_RL, free_RR, instructed_LL, instructed_LR, instructed_RL, instructed_RR);
    
    % Plot 4: Ipsilateral vs Contralateral for LEFT HAND
    %subplot(3, 2, 5);
    %create_ipsi_contra_hand_plot(free_LL, free_LR, free_RL, free_RR, instructed_LL, instructed_LR, instructed_RL, instructed_RR, 'left');
    
    % Plot 5: Ipsilateral vs Contralateral for RIGHT HAND
    %subplot(3, 2, 6);
    %create_ipsi_contra_hand_plot(free_LL, free_LR, free_RL, free_RR, instructed_LL, instructed_LR, instructed_RL, instructed_RR, 'right');
    
    [~, name, ext] = fileparts(filepath);
    sgtitle(sprintf('Comprehensive Analysis - %s%s', name, ext), 'FontSize', 16, 'FontWeight', 'bold');
end

% Combination plots
function create_combination_plot(LL, LR, RL, RR, task_name, success_count, percentage)
    data = [LL, LR, RL, RR];
    colors = [0.2, 0.6, 0.8; 0.4, 0.8, 1.0; 0.4, 1.0, 0.8; 0.2, 0.8, 0.6];
    labels = {'L-H/L-T', 'L-H/R-T', 'R-H/L-T', 'R-H/R-T'};
    
    if sum(data) > 0
        bar_handle = bar(data, 'FaceColor', 'flat');
        bar_handle.CData = colors;
        set(gca, 'XTickLabel', labels, 'FontWeight', 'bold');
        ylabel('Number of trials', 'FontWeight', 'bold');
        
        
        title(sprintf('%s\n%d trials (%.1f%%)', task_name, success_count, percentage), ...
              'FontSize', 12, 'FontWeight', 'bold');
        grid on;
        
       
        total = sum(data);
        for i = 1:4
            if data(i) > 0
                percent_val = (data(i) / total) * 100;
                text(i, data(i), sprintf('%d\n(%.1f%%)', data(i), percent_val), ...
                     'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
                     'FontWeight', 'bold', 'FontSize', 10);
            end
        end
    else
        text(0.5, 0.5, 'No data available', ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
             'FontSize', 12, 'FontWeight', 'bold');
    end
end

% Ipsilateral and contralateral plots
function create_ipsi_contra_plot(free_LL, free_LR, free_RL, free_RR, instructed_LL, instructed_LR, instructed_RL, instructed_RR)
    free_ipsi = free_LL + free_RR;
    free_contra = free_LR + free_RL;
    instructed_ipsi = instructed_LL + instructed_RR;
    instructed_contra = instructed_LR + instructed_RL;
    
    data = [free_ipsi, free_contra; instructed_ipsi, instructed_contra];
    labels = {'Free Choice', 'Instructed'};
    type_labels = {'Ipsilateral', 'Contralateral'};
    
    colors = [1.0, 1.0, 0; 0.8, 0.4, 0.4]; % yellow and red
    
    bar_handle = bar(data, 'grouped');
    
    for i = 1:length(bar_handle)
        bar_handle(i).FaceColor = colors(i,:);
    end
    
    set(gca, 'XTickLabel', labels, 'FontWeight', 'bold');
    ylabel('Number of trials', 'FontWeight', 'bold');
    title('Ipsilateral vs Contralateral Choices', 'FontSize', 12, 'FontWeight', 'bold');
    legend(type_labels, 'Location', 'northeast');
    grid on;
    
    
    for i = 1:2
        total = sum(data(i,:));
        for j = 1:2
            if data(i,j) > 0
                percent_val = (data(i,j) / total) * 100;
                text(i + (j-1.5)*0.2, data(i,j), sprintf('%d\n(%.1f%%)', data(i,j), percent_val), ...
                     'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
                     'FontWeight', 'bold', 'FontSize', 9);
            end
        end
    end
end

% Hand-specific ipsilateral vs contralateral plots
function create_ipsi_contra_hand_plot(free_LL, free_LR, free_RL, free_RR, instructed_LL, instructed_LR, instructed_RL, instructed_RR, hand_type)
    % Calculate ipsilateral vs contralateral for specific hand
    if strcmpi(hand_type, 'left')
        % For LEFT hand: LL=ipsi, LR=contra
        free_ipsi = free_LL;
        free_contra = free_LR;
        instructed_ipsi = instructed_LL;
        instructed_contra = instructed_LR;
        hand_title = 'Left Hand';
        colors = [1.0, 1.0, 0; 0.8, 0.4, 0.4]; % yellow and red
    else
        % For RIGHT hand: RR=ipsi, RL=contra
        free_ipsi = free_RR;
        free_contra = free_RL;
        instructed_ipsi = instructed_RR;
        instructed_contra = instructed_RL;
        hand_title = 'Right Hand';
        colors = [1.0, 1.0, 0; 0.8, 0.4, 0.4]; % yellow and red
    end
    
    data = [free_ipsi, free_contra; instructed_ipsi, instructed_contra];
    labels = {'Free Choice', 'Instructed'};
    type_labels = {'Ipsilateral', 'Contralateral'};
    
    bar_handle = bar(data, 'grouped');
    
    for i = 1:length(bar_handle)
        bar_handle(i).FaceColor = colors(i,:);
    end
    
    set(gca, 'XTickLabel', labels, 'FontWeight', 'bold');
    ylabel('Number of trials', 'FontWeight', 'bold');
    title(sprintf('%s: Ipsilateral vs Contralateral', hand_title), 'FontSize', 12, 'FontWeight', 'bold');
    legend(type_labels, 'Location', 'northeast');
    grid on;
    
   
    for i = 1:2
        total = sum(data(i,:));
        for j = 1:2
            if data(i,j) > 0
                percent_val = (data(i,j) / total) * 100;
                text(i + (j-1.5)*0.2, data(i,j), sprintf('%d\n(%.1f%%)', data(i,j), percent_val), ...
                     'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
                     'FontWeight', 'bold', 'FontSize', 9);
            end
        end
    end
    
    % hand-specific statistics
    free_total = free_ipsi + free_contra;
    instructed_total = instructed_ipsi + instructed_contra;
    
    if free_total > 0
        free_ipsi_percent = (free_ipsi / free_total) * 100;
        text(0.7, max(data(:)) * 0.9, sprintf('Free: %.1f%% ipsi', free_ipsi_percent), ...
             'FontSize', 10, 'FontWeight', 'bold', 'Color', [0.2, 0.2, 0.2]);
    end
    
    if instructed_total > 0
        instructed_ipsi_percent = (instructed_ipsi / instructed_total) * 100;
        text(1.7, max(data(:)) * 0.9, sprintf('Instr: %.1f%% ipsi', instructed_ipsi_percent), ...
             'FontSize', 10, 'FontWeight', 'bold', 'Color', [0.2, 0.2, 0.2]);
    end
end