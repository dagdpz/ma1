function [left_reaches, right_reaches, details] = ma1_reaches_analyze_mp(filepath)
    % REACHES HAND AND TARGET SELECTION ANALYSIS - SIMPLIFIED VERSION
    
    fprintf('LOADING DATA ===\n');
    fprintf('File: %s\n', filepath);
    
    % Load data
    data = load(filepath);
    trials = data.trial;
    
    fprintf('Total trials: %d\n\n', length(trials));
    
    % Counters
    instructed_LL = 0; instructed_LR = 0; instructed_RL = 0; instructed_RR = 0;
    free_LL = 0; free_LR = 0; free_RL = 0; free_RR = 0;
    left_hand_all = 0; right_hand_all = 0;
    left_targets_all = 0; right_targets_all = 0;
    
    % Counters for reach-hand analysis by task type
    free_left_total = 0; free_left_success = 0;
    free_right_total = 0; free_right_success = 0;
    instructed_left_total = 0; instructed_left_success = 0;
    instructed_right_total = 0; instructed_right_success = 0;
    
    
    target_positions = [];
    target_values = [];
    valid_trial_idx = 1:length(trials);
    
    
    for i = 1:length(trials)
        trial = trials(i);
        
        % Basic trial info
        if isfield(trial, 'reach_hand')
            if trial.reach_hand == 1
                left_hand_all = left_hand_all + 1;
            elseif trial.reach_hand == 2
                right_hand_all = right_hand_all + 1;
            end
        end
        
        % Get target position 
        target_position = get_target_pos(trial);
        target_x_position = get_target_x_position(trial);
        
        
        target_positions(i) = target_x_position; %for table...
        target_values(i) = target_position;
        
        % REACH-HAND ANALYSIS BY TASK TYPE
        if isfield(trial, 'reach_hand') && isfield(trial, 'choice')
            if trial.choice == 1 % FREE CHOICE
                if trial.reach_hand == 1
                    free_left_total = free_left_total + 1;
                    if trial.success
                        free_left_success = free_left_success + 1;
                    end
                elseif trial.reach_hand == 2
                    free_right_total = free_right_total + 1;
                    if trial.success
                        free_right_success = free_right_success + 1;
                    end
                end
            else % INSTRUCTED
                if trial.reach_hand == 1
                    instructed_left_total = instructed_left_total + 1;
                    if trial.success
                        instructed_left_success = instructed_left_success + 1;
                    end
                elseif trial.reach_hand == 2
                    instructed_right_total = instructed_right_total + 1;
                    if trial.success
                        instructed_right_success = instructed_right_success + 1;
                    end
                end
            end
        end
        
        % Skip failed trials
        if ~trial.success
            continue;
        end
        
        if ~isnan(target_position)
            if target_position == 1
                left_targets_all = left_targets_all + 1;
            else
                right_targets_all = right_targets_all + 1;
            end
        end
        
        % Skip if missing critical data
        if ~isfield(trial, 'reach_hand') || ~isfield(trial, 'choice') || isnan(target_position)
            continue;
        end
        
        % IPSILATERAL & CONTROLATERAL
        if trial.choice == 0 % INSTRUCTED
            if trial.reach_hand == 1 && target_position == 1
                instructed_LL = instructed_LL + 1;
            elseif trial.reach_hand == 1 && target_position == 2
                instructed_LR = instructed_LR + 1;
            elseif trial.reach_hand == 2 && target_position == 1
                instructed_RL = instructed_RL + 1;
            elseif trial.reach_hand == 2 && target_position == 2
                instructed_RR = instructed_RR + 1;
            end
        else % FREE CHOICE
            if trial.reach_hand == 1 && target_position == 1
                free_LL = free_LL + 1;
            elseif trial.reach_hand == 1 && target_position == 2
                free_LR = free_LR + 1;
            elseif trial.reach_hand == 2 && target_position == 1
                free_RL = free_RL + 1;
            elseif trial.reach_hand == 2 && target_position == 2
                free_RR = free_RR + 1;
            end
        end
    end
    
    % Display results
    display_results(trials, instructed_LL, instructed_LR, instructed_RL, instructed_RR, ...
                   free_LL, free_LR, free_RL, free_RR, left_hand_all, right_hand_all, ...
                   left_targets_all, right_targets_all);
    
    % DISPLAY REACH-HAND ANALYSIS BY TASK TYPE
    display_reach_hand_analysis(free_left_total, free_left_success, free_right_total, free_right_success, ...
                               instructed_left_total, instructed_left_success, instructed_right_total, instructed_right_success);
    
    % SUMMARY TABLE
    has_choice_field = isfield(trials, 'choice');
    create_summary_table(trials, valid_trial_idx, has_choice_field, target_positions, target_values, filepath);
    
    % PLOTS
    if has_choice_field
        free_success_count = free_LL + free_LR + free_RL + free_RR;
        instructed_success_count = instructed_LL + instructed_LR + instructed_RL + instructed_RR;
        total_success_count = sum([trials.success] == 1);
        
        if total_success_count > 0
            free_percentage = (free_success_count / total_success_count) * 100;
            instructed_percentage = (instructed_success_count / total_success_count) * 100;
        else
            free_percentage = 0;
            instructed_percentage = 0;
        end
        
        create_all_plots(free_LL, free_LR, free_RL, free_RR, instructed_LL, instructed_LR, instructed_RL, instructed_RR, ...
                        free_success_count, free_percentage, instructed_success_count, instructed_percentage, ...
                        total_success_count, filepath);
    end
    
    % Outputs
    left_reaches = left_hand_all;
    right_reaches = right_hand_all;
    
    details.all_trials = length(trials);
    details.successful_trials = sum([trials.success] == 1);
    details.failed_trials = sum([trials.success] == 0);
    details.left_reaches = left_hand_all;
    details.right_reaches = right_hand_all;
    details.left_targets = left_targets_all;
    details.right_targets = right_targets_all;
    
    if isfield(trials, 'choice')
        details.free_combinations = [free_LL, free_LR, free_RL, free_RR];
        details.instructed_combinations = [instructed_LL, instructed_LR, instructed_RL, instructed_RR];

        % Add reach-hand analysis dara
        details.free_left_total = free_left_total;
        details.free_left_success = free_left_success;
        details.free_right_total = free_right_total;
        details.free_right_success = free_right_success;
        details.instructed_left_total = instructed_left_total;
        details.instructed_left_success = instructed_left_success;
        details.instructed_right_total = instructed_right_total;
        details.instructed_right_success = instructed_right_success;
    end

function position = get_target_pos(trial)
    % Target position based on x_hnd at state=5
    position = NaN;
    
    if isfield(trial, 'x_hnd') && isfield(trial, 'state') && ...
       ~isempty(trial.x_hnd) && ~isempty(trial.state)
        
        state5_indices = find(trial.state == 5);
        if ~isempty(state5_indices)
            last_state5_idx = state5_indices(end);
            if last_state5_idx <= length(trial.x_hnd)
                final_x_value = trial.x_hnd(last_state5_idx);
                if final_x_value < 0
                    position = 1; % Left side
                elseif final_x_value > 0
                    position = 2; % Right side
                end
            end
        end
    end

function x_position = get_target_x_position(trial)
    % the actual x position value at state=5
    x_position = NaN;
    
    if isfield(trial, 'x_hnd') && isfield(trial, 'state') && ...
       ~isempty(trial.x_hnd) && ~isempty(trial.state)
        
        state5_indices = find(trial.state == 5);
        if ~isempty(state5_indices)
            last_state5_idx = state5_indices(end);
            if last_state5_idx <= length(trial.x_hnd)
                x_position = trial.x_hnd(last_state5_idx);
            end
        end
    end

function display_results(trials, instructed_LL, instructed_LR, instructed_RL, instructed_RR, ...
                        free_LL, free_LR, free_RL, free_RR, left_hand_all, right_hand_all, ...
                        left_targets_all, right_targets_all)
    % SUMMARY
    
    fprintf('\n=== SUMMARY ===\n');
    fprintf('Total trials: %d\n', length(trials));
    fprintf('Successful trials: %d\n', sum([trials.success] == 1));
    fprintf('Failed trials: %d\n', sum([trials.success] == 0));
    fprintf('Left hand reaches: %d\n', left_hand_all);
    fprintf('Right hand reaches: %d\n', right_hand_all);
    fprintf('Left targets: %d\n', left_targets_all);
    fprintf('Right targets: %d\n', right_targets_all);
    
    fprintf('\n=== HAND-TARGET COMBINATIONS ===\n');
    fprintf('INSTRUCTED: LL=%d, LR=%d, RL=%d, RR=%d\n', instructed_LL, instructed_LR, instructed_RL, instructed_RR);
    fprintf('FREE CHOICE: LL=%d, LR=%d, RL=%d, RR=%d\n', free_LL, free_LR, free_RL, free_RR);
    
    instructed_total = instructed_LL + instructed_LR + instructed_RL + instructed_RR;
    free_total = free_LL + free_LR + free_RL + free_RR;
    
    if instructed_total > 0
        fprintf('INSTRUCTED: Ipsilateral=%.1f%%, Contralateral=%.1f%%\n', ...
            (instructed_LL + instructed_RR)/instructed_total*100, ...
            (instructed_LR + instructed_RL)/instructed_total*100);
    end
    
    if free_total > 0
        fprintf('FREE CHOICE: Ipsilateral=%.1f%%, Contralateral=%.1f%%\n', ...
            (free_LL + free_RR)/free_total*100, ...
            (free_LR + free_RL)/free_total*100);
    end
    
    

function display_reach_hand_analysis(free_left_total, free_left_success, free_right_total, free_right_success, ...
                                   instructed_left_total, instructed_left_success, instructed_right_total, instructed_right_success)
    % Reach-hand analysis by task type
    
    fprintf('\n=== REACH-HAND ANALYSIS BY TASK TYPE ===\n');
    
    % FREE CHOICE TASK
    fprintf('FREE CHOICE TASK:\n');
    fprintf('  Left hand reaches (in total): %d\n', free_left_total);
    fprintf('  Left hand reaches (only success): %d\n', free_left_success);
    fprintf('  Right hand reaches (in total): %d\n', free_right_total);
    fprintf('  Right hand reaches (only success): %d\n', free_right_success);
    
   
    if free_left_total > 0
        free_left_success_percent = (free_left_success / free_left_total) * 100;
    else
        free_left_success_percent = 0;
    end
    if free_right_total > 0
        free_right_success_percent = (free_right_success / free_right_total) * 100;
    else
        free_right_success_percent = 0;
    end
    
    fprintf('     Success rates: Left=%.1f%%, Right=%.1f%%\n', free_left_success_percent, free_right_success_percent);
    
    % INSTRUCTED TASK
    fprintf('INSTRUCTED TASK:\n');
    fprintf('  Left hand reaches (in total): %d\n', instructed_left_total);
    fprintf('  Left hand reaches (only success): %d\n', instructed_left_success);
    fprintf('  Right hand reaches (in total): %d\n', instructed_right_total);
    fprintf('  Right hand reaches (only success): %d\n', instructed_right_success);
    
    
    if instructed_left_total > 0
        instructed_left_success_percent = (instructed_left_success / instructed_left_total) * 100;
    else
        instructed_left_success_percent = 0;
    end
    if instructed_right_total > 0
        instructed_right_success_percent = (instructed_right_success / instructed_right_total) * 100;
    else
        instructed_right_success_percent = 0;
    end
    
    fprintf('     Success rates: Left=%.1f%%, Right=%.1f%%\n', instructed_left_success_percent, instructed_right_success_percent);

    fprintf('\n=== ANALYSIS COMPLETED ===\n');

function create_summary_table(trials, valid_trial_idx, has_choice_field, target_positions, target_values, filepath)
    fprintf('Creating summary table for all trials...\n');
    
    num_trials = length(valid_trial_idx);
    trial_numbers = zeros(num_trials, 1);
    task_types = cell(num_trials, 1);
    reach_hands = cell(num_trials, 1);
    target_choices = cell(num_trials, 1);
    coordinates = zeros(num_trials, 1);
    success_status = cell(num_trials, 1);
    
    for i = 1:num_trials
        trial_idx = valid_trial_idx(i);
        
        trial_numbers(i) = trial_idx;
        
        if has_choice_field
            if trials(trial_idx).choice == 1
                task_types{i} = 'Free';
            else
                task_types{i} = 'Instructed';
            end
        else
            task_types{i} = 'Unknown';
        end
        
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
        
        if ~isnan(target_positions(i))
            coordinates(i) = target_positions(i);
        else
            coordinates(i) = NaN;
        end
        
        if trials(trial_idx).success == 1
            success_status{i} = '✓';
        else
            success_status{i} = '✗';
        end
    end
    
    summary_table = table(trial_numbers, task_types, reach_hands, target_choices, coordinates, success_status, ...
        'VariableNames', {'Trial', 'TaskType', 'ReachHand', 'TargetChoice', 'TargetX', 'Success'});
    
    fig = figure('Position', [100, 100, 900, 600], 'Name', 'Complete Trial Summary Table');
    
    t = uitable(fig, 'Data', table2cell(summary_table), ...
        'ColumnName', {'Trial', 'Task Type', 'Reach Hand', 'Target Choice', 'Target X', 'Success'}, ...
        'ColumnWidth', {60, 80, 80, 80, 80, 60}, ...
        'Position', [20, 50, 860, 500], ...
        'RowName', []);
    
    [~, name, ext] = fileparts(filepath);
    uicontrol('Style', 'text', ...
        'String', sprintf('Complete Trial Summary - %s%s', name, ext), ...
        'Position', [20, 560, 860, 30], ...
        'FontSize', 14, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center');
    
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

function create_all_plots(free_LL, free_LR, free_RL, free_RR, instructed_LL, instructed_LR, instructed_RL, instructed_RR, ...
                         free_success_count, free_percentage, instructed_success_count, instructed_percentage, ...
                         total_success_count, filepath)
    
    fig = figure('Position', [50, 50, 1400, 1000], 'Name', 'Comprehensive Analysis Results');
    
    subplot(2, 2, 1);
    create_combination_plot(free_LL, free_LR, free_RL, free_RR, 'Free Choice', free_success_count, free_percentage);
    
    subplot(2, 2, 2);
    create_combination_plot(instructed_LL, instructed_LR, instructed_RL, instructed_RR, 'Instructed', instructed_success_count, instructed_percentage);
    
    subplot(2, 2, 3);
    create_ipsi_contra_plot(free_LL, free_LR, free_RL, free_RR, instructed_LL, instructed_LR, instructed_RL, instructed_RR);
    
    [~, name, ext] = fileparts(filepath);
    sgtitle(sprintf('Comprehensive Analysis - %s%s', name, ext), 'FontSize', 16, 'FontWeight', 'bold');

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

function create_ipsi_contra_plot(free_LL, free_LR, free_RL, free_RR, instructed_LL, instructed_LR, instructed_RL, instructed_RR)
    free_ipsi = free_LL + free_RR;
    free_contra = free_LR + free_RL;
    instructed_ipsi = instructed_LL + instructed_RR;
    instructed_contra = instructed_LR + instructed_RL;
    
    data = [free_ipsi, free_contra; instructed_ipsi, instructed_contra];
    labels = {'Free Choice', 'Instructed'};
    type_labels = {'Ipsilateral', 'Contralateral'};
    
    colors = [1.0, 1.0, 0; 0.8, 0.4, 0.4];
    
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