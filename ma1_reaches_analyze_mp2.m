function details = ma1_reaches_analyze_mp2(input_path, animal_name, session_date, n_before, n_after)
% ma1_reaches_analyze_mp2 - Modernized daily analysis with silent CLI and Excel export.K>> ma1_reaches_analyze_mp2('Y:\Data\Feno\20260504')
%
% Requirements implemented:
% - No output in Command Window (no fprintf/warning output).
% - Prompt user at end of experiment:
%     "Enter the number of blocks (runs) before injection and after injection:"
% - Analyze run-by-run (block-by-block).
% - Export one Excel file with 6 sheets:
%     Sheet 1: Calculated parameters before injection
%     Sheet 2: Analysis plots before injection
%     Sheet 3: Calculated parameters after injection
%     Sheet 4: Analysis plots after injection
%     Sheet 5: Trial-by-trial data before injection
%     Sheet 6: Trial-by-trial data after injection
% - Include all runs recorded on same experimental day (all *.mat in same folder).
%
% Usage:
%   details = ma1_reaches_analyze_mp2('/path/to/one_run.mat', 'Fen');
%   details = ma1_reaches_analyze_mp2('/path/to/day_folder', 'Fen', datetime(2025,11,18));
%   details = ma1_reaches_analyze_mp2('/path/to/day_folder', 'Fen', datetime(2025,11,18), 1, 2);
%     % Last two arguments: n_before, n_after (optional - will prompt if not provided)

    % Keep MATLAB quiet
    prevWarn = warning('query', 'all');
    warning('off', 'all');
    c = onCleanup(@() warning(prevWarn));

    if nargin < 1 || isempty(input_path)
        error('Input path is required (file or folder).');
    end
    if nargin < 2 || isempty(animal_name)
        animal_name = infer_animal_name(input_path);
    end
    if nargin < 3 || isempty(session_date)
        session_date = datetime('today');
    end

    % Collect all run files for the day
    run_files = list_day_runs(input_path);
    if isempty(run_files)
        error('No .mat files found for the day.');
    end

    % Prompt at end of experiment for blocks before/after injection (if not provided)
    if nargin < 4 || isempty(n_before) || nargin < 5 || isempty(n_after)
        [n_before, n_after] = prompt_blocks_before_after();
    end
    if n_before + n_after > numel(run_files)
        error('Not enough runs found: requested %d (before+after), found %d.', n_before+n_after, numel(run_files));
    end

    before_files = run_files(1:n_before);
    after_files  = run_files((n_before+1):(n_before+n_after));

    % Analyze each run and build parameter tables
    before_tbl = analyze_runs_to_table(before_files, 'Before');
    after_tbl  = analyze_runs_to_table(after_files,  'After');
    
    % Create trial-by-trial detailed tables
    before_trials_tbl = analyze_runs_to_trial_table(before_files, 'Before');
    after_trials_tbl  = analyze_runs_to_trial_table(after_files,  'After');

    % Create plots (same style as older MATLAB plots) and save as PNGs
    out_dir = ensure_output_dir(animal_name);
    date_str = datestr(session_date, 'yyyy-mm-dd');
    excel_filename = sprintf('%s_%s.xlsx', animal_name, date_str);
    excel_fullpath = fullfile(out_dir, excel_filename);

    % Create plots and save as PNG files (no Excel sheets for plots)
    before_base = sprintf('%s_%s_before', animal_name, date_str);
    after_base  = sprintf('%s_%s_after',  animal_name, date_str);

    before_plot_paths = make_plots_for_condition(before_tbl, out_dir, before_base);
    before_delay_plots = make_delay_duration_plots(before_trials_tbl, out_dir, before_base);
    before_tacq_plots = make_target_acquisition_plots(before_trials_tbl, out_dir, before_base);
    before_plot_paths = [before_plot_paths; before_delay_plots; before_tacq_plots];

    % If n_after == 0, skip all "after" plots (prevents errors on empty input)
    after_plot_paths = {};
    if n_after > 0
        after_plot_paths  = make_plots_for_condition(after_tbl,  out_dir, after_base);
        after_delay_plots  = make_delay_duration_plots(after_trials_tbl,  out_dir, after_base);
        after_tacq_plots  = make_target_acquisition_plots(after_trials_tbl,  out_dir, after_base);
        after_plot_paths = [after_plot_paths; after_delay_plots; after_tacq_plots];
    end

    % Export to Excel
    write_tables_to_excel(excel_fullpath, before_tbl, after_tbl, before_trials_tbl, after_trials_tbl);

    % Return details struct
    details = struct();
    details.animal_name = animal_name;
    details.session_date = session_date;
    details.run_files = run_files;
    details.n_before = n_before;
    details.n_after = n_after;
    details.excel_fullpath = excel_fullpath;
    details.before_plot_files = before_plot_paths;
    details.after_plot_files = after_plot_paths;
    details.before_table = before_tbl;
    details.after_table = after_tbl;
    details.before_trials_table = before_trials_tbl;
    details.after_trials_table = after_trials_tbl;
    
    % Display completion message
    fprintf('\nAnalysis complete successfully, data saved in %s\n', out_dir);

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

% =========================
% Modernized helpers
% =========================

function animal_name = infer_animal_name(input_path)
    if isfolder(input_path)
        [~, animal_name] = fileparts(input_path);
        return;
    end
    [parent_path, ~, ~] = fileparts(input_path);
    [~, animal_name] = fileparts(parent_path);

function run_files = list_day_runs(input_path)
    if isfolder(input_path)
        day_dir = input_path;
    else
        day_dir = fileparts(input_path);
    end
    d = dir(fullfile(day_dir, '*.mat'));
    if isempty(d)
        run_files = {};
        return;
    end
    % Sort by name (typical *_01, *_02, ...). If you need by date, change here.
    [~, idx] = sort({d.name});
    d = d(idx);
    run_files = fullfile({d.folder}, {d.name});

function [n_before, n_after] = prompt_blocks_before_after()
    prompt = "Enter the number of blocks (runs) before injection and after injection:";
    while true
        s = strtrim(input(prompt + newline, 's'));
        nums = sscanf(s, '%d %d');
        if numel(nums) == 2 && all(nums >= 0)
            n_before = nums(1);
            n_after = nums(2);
            return;
        end
    end

function out_dir = ensure_output_dir(animal_name)
    % Use current directory or create exel folder in user's Documents
    if ispc
        base_excel_dir = fullfile(getenv('USERPROFILE'), 'Documents', 'exel');
    else
        base_excel_dir = fullfile(getenv('HOME'), 'Documents', 'exel');
    end
    out_dir = fullfile(base_excel_dir, animal_name);
    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end

function tbl = analyze_runs_to_table(run_files, condition_label)
    n = numel(run_files);
    if n == 0
        tbl = empty_run_summary_table(condition_label);
        return;
    end
    rows = cell(n, 1);
    for k = 1:n
        rows{k} = analyze_single_run(run_files{k}, k, condition_label);
    end
    tbl = vertcat(rows{:});

function tbl = empty_run_summary_table(condition_label)
    % Return an empty table with the same variables as analyze_single_run output.
    % This prevents dot-indexing errors when n_before or n_after is 0.
    varNames = { ...
        'Condition','Run','File','AllTrials','InitiatedTrials','SuccessfulTrials','FailedTrials', ...
        'PctInitiatedOfAll','PctSuccessfulOfAll','PctSuccessfulOfInitiated', ...
        'LeftHandAll','RightHandAll','LeftTargets','RightTargets', ...
        'Instr_LL','Instr_LR','Instr_RL','Instr_RR', ...
        'Free_LL','Free_LR','Free_RL','Free_RR', ...
        'FreeLeftTotal','FreeLeftSuccess','FreeLeftSuccessPct', ...
        'FreeRightTotal','FreeRightSuccess','FreeRightSuccessPct', ...
        'InstrLeftTotal','InstrLeftSuccess','InstrLeftSuccessPct', ...
        'InstrRightTotal','InstrRightSuccess','InstrRightSuccessPct', ...
        'abort_use_incorrect_hand','abort_hnd_fix_acq_state','abort_hnd_del_per_state', ...
        'abort_hnd_tar_acq_state','abort_hnd_fix_hold_state' ...
    };
    varTypes = [{ 'string','double','string' }, repmat({'double'}, 1, numel(varNames)-3)];
    tbl = table('Size',[0 numel(varNames)], 'VariableTypes', varTypes, 'VariableNames', varNames);
    tbl.Condition = repmat(string(condition_label), 0, 1);

function tbl = analyze_runs_to_trial_table(run_files, condition_label)
    % Create a detailed trial-by-trial table with delay duration and success status
    n = numel(run_files);
    all_trial_tables = cell(n, 1);
    
    for k = 1:n
        all_trial_tables{k} = analyze_single_run_trials(run_files{k}, k, condition_label);
    end
    
    % Concatenate all trial tables
    if n == 0 || all(cellfun(@isempty, all_trial_tables))
        % Create empty table with correct structure
        tbl = table( ...
            string([]), int32([]), int32([]), string([]), ...
            string([]), double([]), double([]), string([]), string([]), ...
            double([]), string([]), double([]), ...
            'VariableNames', {'Condition', 'Run', 'Trial', 'File', 'TaskType', 'DelayDuration', 'TargetAcqTime', 'Target', 'Hand', 'Success', 'reason_of_abort', 'TimeUntilAbort'});
    else
        % Remove empty tables
        non_empty = ~cellfun(@isempty, all_trial_tables);
        if any(non_empty)
            tbl = vertcat(all_trial_tables{non_empty});
        else
            tbl = table( ...
                string([]), int32([]), int32([]), string([]), ...
                string([]), double([]), double([]), string([]), string([]), ...
                double([]), string([]), double([]), ...
                'VariableNames', {'Condition', 'Run', 'Trial', 'File', 'TaskType', 'DelayDuration', 'TargetAcqTime', 'Target', 'Hand', 'Success', 'reason_of_abort', 'TimeUntilAbort'});
        end
    end

function trial_rows = analyze_single_run_trials(filepath, run_index, condition_label)
    % Extract trial-by-trial data including delay duration, success, task type, target, hand, abort reason
    data = load(filepath);
    if ~isfield(data, 'trial')
        error('File does not contain variable "trial": %s', filepath);
    end
    trials = normalize_trials(data.trial);
    
    n_trials = length(trials);
    if n_trials == 0
        trial_rows = cell(0, 1);
        return;
    end
    
    % Preallocate arrays
    condition_col = repmat(string(condition_label), n_trials, 1);
    run_col = repmat(int32(run_index), n_trials, 1);
    trial_col = int32(1:n_trials)';
    file_col = repmat(string(filepath), n_trials, 1);
    task_type_col = repmat(string(""), n_trials, 1);
    delay_col = NaN(n_trials, 1);
    target_acq_time_col = NaN(n_trials, 1);
    target_col = repmat(string(""), n_trials, 1);
    hand_col = repmat(string(""), n_trials, 1);
    success_col = zeros(n_trials, 1);
    abort_reason_col = repmat(string(""), n_trials, 1);
    time_until_abort_col = NaN(n_trials, 1);
    
    for i = 1:n_trials
        trial = trials(i);
        if ~isstruct(trial)
            continue;
        end
        
        % Extract task type (choice field: 0=instructed, 1=free)
        if isfield(trial, 'choice')
            if trial.choice == 1
                task_type_col(i) = "Free";
            else
                task_type_col(i) = "Instructed";
            end
        end
        
        % Extract delay period duration (State 8: DEL_PER)
        if isfield(trial, 'states') && isfield(trial, 'states_onset')
            delay_idx = find(trial.states == 8, 1);  % DEL_PER
            if ~isempty(delay_idx) && delay_idx < length(trial.states_onset)
                delay_col(i) = trial.states_onset(delay_idx + 1) - trial.states_onset(delay_idx);
            end
            % Hand movement time: end of delay period (state 8) → start of target hold (state 5)
            if ~isempty(delay_idx) && delay_idx + 1 <= length(trial.states_onset)
                end_delay = trial.states_onset(delay_idx + 1);
                idx5 = find(trial.states == 5);
                idx5_after_delay = idx5(idx5 > delay_idx);
                if ~isempty(idx5_after_delay) && idx5_after_delay(1) <= length(trial.states_onset)
                    start_hold = trial.states_onset(idx5_after_delay(1));
                    target_acq_time_col(i) = start_hold - end_delay;
                end
            end
        end
        
        % Extract target position
        target_pos = get_target_pos(trial); % 1 left, 2 right
        if target_pos == 1
            target_col(i) = "Left";
        elseif target_pos == 2
            target_col(i) = "Right";
        end
        
        % Extract hand (reach_hand: 1=left, 2=right)
        if isfield(trial, 'reach_hand')
            rh = get_scalar_num_field(trial, 'reach_hand');
            if rh == 1
                hand_col(i) = "Left";
            elseif rh == 2
                hand_col(i) = "Right";
            end
        end
        
        % Extract success status
        if isfield(trial, 'success')
            success_col(i) = double(trial.success);
        else
            success_col(i) = NaN;
        end
        
        % Extract abort reason (if trial failed) - convert to lowercase
        if ~isnan(success_col(i)) && success_col(i) == 0
            reason = get_abort_reason(trial);
            if ~isempty(reason)
                abort_reason_col(i) = string(lower(reason));
            else
                abort_reason_col(i) = "";
            end
            % Time until abort for abort_hnd_del_per_state (from delay start to trial end)
            if contains(lower(reason), 'abort_hnd_del_per_state') && isfield(trial, 'states') && isfield(trial, 'states_onset')
                delay_idx = find(trial.states == 8, 1);
                if ~isempty(delay_idx) && length(trial.states_onset) >= delay_idx
                    time_until_abort_col(i) = trial.states_onset(end) - trial.states_onset(delay_idx);
                end
            end
        else
            abort_reason_col(i) = "";
        end
    end
    
    % Create table for all trials in this run
    trial_rows = table( ...
        condition_col, ...
        run_col, ...
        trial_col, ...
        file_col, ...
        task_type_col, ...
        delay_col, ...
        target_acq_time_col, ...
        target_col, ...
        hand_col, ...
        success_col, ...
        abort_reason_col, ...
        time_until_abort_col, ...
        'VariableNames', {'Condition', 'Run', 'Trial', 'File', 'TaskType', 'DelayDuration', 'TargetAcqTime', 'Target', 'Hand', 'Success', 'reason_of_abort', 'TimeUntilAbort'});

function run_tbl = analyze_single_run(filepath, run_index, condition_label)
    data = load(filepath);
    if ~isfield(data, 'trial')
        error('File does not contain variable "trial": %s', filepath);
    end
    trials = normalize_trials(data.trial);

    % Basic counts
    all_trials = length(trials);
    successful_trials = 0;
    failed_trials = 0;
    for ii = 1:all_trials
        if ~isstruct(trials(ii)) || ~isfield(trials(ii), 'success') || isempty(trials(ii).success)
            continue;
        end
        s = double(trials(ii).success(1));
        if s == 1
            successful_trials = successful_trials + 1;
        elseif s == 0
            failed_trials = failed_trials + 1;
        end
    end
    initiated_trials = successful_trials + failed_trials;

    % Reach hand counts (all trials) - robust to non-scalar reach_hand
    left_hand_all = 0;
    right_hand_all = 0;
    for ii = 1:length(trials)
        rh = get_scalar_num_field(trials(ii), 'reach_hand');
        if rh == 1
            left_hand_all = left_hand_all + 1;
        elseif rh == 2
            right_hand_all = right_hand_all + 1;
        end
    end

    % Compute target side (only success, consistent with old logic)
    left_targets_all = 0;
    right_targets_all = 0;

    instructed_LL = 0; instructed_LR = 0; instructed_RL = 0; instructed_RR = 0;
    free_LL = 0; free_LR = 0; free_RL = 0; free_RR = 0;

    % Delay period outcomes (if available)
    delay_success_count = 0;
    delay_fail_count = 0;
    delay_total_known = 0;

    % Aborted trials - count by abort reason type
    abort_use_incorrect_hand = 0;
    abort_hnd_fix_acq_state = 0;
    abort_hnd_del_per_state = 0;
    abort_hnd_tar_acq_state = 0;
    abort_hnd_fix_hold_state = 0;

    % Reach-hand analysis by task type
    free_left_total = 0; free_left_success = 0;
    free_right_total = 0; free_right_success = 0;
    instructed_left_total = 0; instructed_left_success = 0;
    instructed_right_total = 0; instructed_right_success = 0;

    for i = 1:length(trials)
        trial = trials(i);
        if ~isstruct(trial) || ~isfield(trial, 'success') || isempty(trial.success)
            continue;
        end

        target_position = get_target_pos(trial); % 1 left, 2 right

        if isfield(trial, 'reach_hand') && isfield(trial, 'choice')
            if trial.choice == 1 % FREE
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

        % Count aborted trials by reason type (all failed trials) - do this BEFORE continue
        if ~trial.success
            reason = get_abort_reason(trial);
            if ~isempty(reason)
                reason_lower = lower(reason);
                if contains(reason_lower, 'abort_use_incorrect_hand')
                    abort_use_incorrect_hand = abort_use_incorrect_hand + 1;
                elseif contains(reason_lower, 'abort_hnd_fix_acq_state')
                    abort_hnd_fix_acq_state = abort_hnd_fix_acq_state + 1;
                elseif contains(reason_lower, 'abort_hnd_del_per_state')
                    abort_hnd_del_per_state = abort_hnd_del_per_state + 1;
                elseif contains(reason_lower, 'abort_hnd_tar_acq_state')
                    abort_hnd_tar_acq_state = abort_hnd_tar_acq_state + 1;
                elseif contains(reason_lower, 'abort_hnd_fix_hold_state')
                    abort_hnd_fix_hold_state = abort_hnd_fix_hold_state + 1;
                end
            end
        end

        if ~trial.success
            continue;
        end

        if ~isnan(target_position)
            if target_position == 1
                left_targets_all = left_targets_all + 1;
            elseif target_position == 2
                right_targets_all = right_targets_all + 1;
            end
        end

        if ~isfield(trial, 'reach_hand') || ~isfield(trial, 'choice') || isnan(target_position)
            continue;
        end

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
        else % FREE
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

        % Delay outcome
        d_outcome = get_delay_outcome(trial); % 1 success, 0 fail, NaN unknown
        if ~isnan(d_outcome)
            delay_total_known = delay_total_known + 1;
            if d_outcome == 1
                delay_success_count = delay_success_count + 1;
            elseif d_outcome == 0
                delay_fail_count = delay_fail_count + 1;
            end
        end
    end

    % Success percentages
    if all_trials > 0
        pct_initiated_all = initiated_trials / all_trials * 100;
        pct_success_all = successful_trials / all_trials * 100;
    else
        pct_initiated_all = NaN;
        pct_success_all = NaN;
    end
    if initiated_trials > 0
        pct_success_initiated = successful_trials / initiated_trials * 100;
    else
        pct_success_initiated = NaN;
    end

    % Reach-hand success rates
    free_left_sr = safe_pct(free_left_success, free_left_total);
    free_right_sr = safe_pct(free_right_success, free_right_total);
    instructed_left_sr = safe_pct(instructed_left_success, instructed_left_total);
    instructed_right_sr = safe_pct(instructed_right_success, instructed_right_total);

    run_tbl = table( ...
        string(condition_label), run_index, string(filepath), all_trials, initiated_trials, successful_trials, failed_trials, ...
        pct_initiated_all, pct_success_all, pct_success_initiated, ...
        left_hand_all, right_hand_all, left_targets_all, right_targets_all, ...
        instructed_LL, instructed_LR, instructed_RL, instructed_RR, ...
        free_LL, free_LR, free_RL, free_RR, ...
        free_left_total, free_left_success, free_left_sr, ...
        free_right_total, free_right_success, free_right_sr, ...
        instructed_left_total, instructed_left_success, instructed_left_sr, ...
        instructed_right_total, instructed_right_success, instructed_right_sr, ...
        abort_use_incorrect_hand, abort_hnd_fix_acq_state, abort_hnd_del_per_state, ...
        abort_hnd_tar_acq_state, abort_hnd_fix_hold_state, ...
        'VariableNames', { ...
            'Condition','Run','File','AllTrials','InitiatedTrials','SuccessfulTrials','FailedTrials', ...
            'PctInitiatedOfAll','PctSuccessfulOfAll','PctSuccessfulOfInitiated', ...
            'LeftHandAll','RightHandAll','LeftTargets','RightTargets', ...
            'Instr_LL','Instr_LR','Instr_RL','Instr_RR', ...
            'Free_LL','Free_LR','Free_RL','Free_RR', ...
            'FreeLeftTotal','FreeLeftSuccess','FreeLeftSuccessPct', ...
            'FreeRightTotal','FreeRightSuccess','FreeRightSuccessPct', ...
            'InstrLeftTotal','InstrLeftSuccess','InstrLeftSuccessPct', ...
            'InstrRightTotal','InstrRightSuccess','InstrRightSuccessPct', ...
            'abort_use_incorrect_hand','abort_hnd_fix_acq_state','abort_hnd_del_per_state', ...
            'abort_hnd_tar_acq_state','abort_hnd_fix_hold_state' ...
        });

function trials = normalize_trials(trials)
    % Normalize loaded `trial` to a struct array; drop non-struct entries.
    if isempty(trials)
        trials = struct([]);
        return;
    end
    if iscell(trials)
        trials = trials(:);
        is_ok = cellfun(@(t) isstruct(t) && ~isempty(t), trials);
        if any(is_ok)
            trials = [trials{is_ok}];
        else
            trials = struct([]);
        end
        return;
    end
    if ~isstruct(trials)
        trials = struct([]);
        return;
    end
    % Struct array: keep as-is
 

function pct = safe_pct(x, n)
    if n > 0
        pct = x / n * 100;
    else
        pct = NaN;
    end

function v = get_scalar_num_field(tr, fieldname)
    % Returns a scalar numeric value from a field or NaN if missing/invalid.
    v = NaN;
    if ~isfield(tr, fieldname)
        return;
    end
    val = tr.(fieldname);
    if isempty(val) || ~isnumeric(val)
        return;
    end
    v = val(1);

function d = get_delay_outcome(tr)
    % Returns 1 (success), 0 (fail), or NaN (unknown) for delay period outcome.
    % Tries several possible field names/types.
    d = NaN;
    try
        if isempty(tr) || ~isstruct(tr)
            return;
        end
        candidate_fields = {'delay_success','delaySuccess','delay_outcome','delayOutcome','delay'};
        for i = 1:numel(candidate_fields)
            fn = candidate_fields{i};
            try
                if ~isfield(tr, fn)
                    continue;
                end
                val = tr.(fn);
            catch
                continue;
            end
            if isempty(val)
                continue;
            end
            if islogical(val) || isnumeric(val)
                v = val(1);
                if v == 1
                    d = 1; return;
                elseif v == 0
                    d = 0; return;
                end
            elseif ischar(val) || isstring(val)
                sval = lower(string(val(1)));
                if sval == "success"
                    d = 1; return;
                elseif sval == "fail" || sval == "failure" || sval == "unsuccessful"
                    d = 0; return;
                end
            end
        end
    catch
        d = NaN;
    end

function f = get_aborted_flag(tr)
    % Returns 1 if trial is marked as aborted in any reasonable field, else 0.
    f = 0;
    if isempty(tr) || ~isstruct(tr)
        return;
    end
    candidate_fields = {'aborted','abort','isAborted','trial_aborted','is_abort'};
    for i = 1:numel(candidate_fields)
        fn = candidate_fields{i};
        if isfield(tr, fn)
            val = tr.(fn);
            if isempty(val)
                continue;
            end
            if islogical(val) || isnumeric(val)
                v = val(1);
                if v ~= 0
                    f = 1;
                    return;
                end
            elseif ischar(val) || isstring(val)
                sval = lower(string(val(1)));
                if sval == "aborted" || sval == "abort" || sval == "yes" || sval == "true"
                    f = 1;
                    return;
                end
            end
        end
    end

function reason = get_abort_reason(tr)
    % Returns a short text label describing abort reason, or '' if unknown.
    % Priority: abort_code (most common) > abort_reason > other fields
    reason = '';
    try
        if isempty(tr) || ~isstruct(tr)
            return;
        end
        candidate_fields = {'abort_code','abortCode','abort_reason','abortReason','aborted_reason', ...
                            'error','error_code','errorCode','fail_reason','failReason'};
        for i = 1:numel(candidate_fields)
            fn = candidate_fields{i};
            try
                if ~isfield(tr, fn)
                    continue;
                end
                val = tr.(fn);
            catch
                continue;
            end
            if isempty(val)
                continue;
            end
            if ischar(val)
                reason = strtrim(val);
                if ~isempty(reason)
                    return;
                end
            elseif isstring(val)
                s = strtrim(string(val));
                if s ~= ""
                    reason = char(s);
                    return;
                end
            elseif isnumeric(val)
                reason = sprintf('%s_%g', fn, val(1));
                return;
            end
        end
    catch
        reason = '';
    end

function plot_paths = make_plots_for_condition(tbl, out_dir, base_name)
    % Create the same plots as before, but aggregated across runs:
    % - Combination counts (Free and Instructed)
    % - Ipsi vs Contra
    %
    % Save each figure as PNG (offscreen). Plots are saved to folder, not Excel.

    plot_paths = {};
    if isempty(tbl) || ~istable(tbl) || height(tbl) == 0
        return;
    end

    % Aggregate across runs
    sum_free_LL = nansum(tbl.Free_LL);
    sum_free_LR = nansum(tbl.Free_LR);
    sum_free_RL = nansum(tbl.Free_RL);
    sum_free_RR = nansum(tbl.Free_RR);
    sum_instr_LL = nansum(tbl.Instr_LL);
    sum_instr_LR = nansum(tbl.Instr_LR);
    sum_instr_RL = nansum(tbl.Instr_RL);
    sum_instr_RR = nansum(tbl.Instr_RR);

    total_success = nansum(tbl.SuccessfulTrials);
    free_success = sum_free_LL + sum_free_LR + sum_free_RL + sum_free_RR;
    instr_success = sum_instr_LL + sum_instr_LR + sum_instr_RL + sum_instr_RR;
    free_pct = safe_pct(free_success, total_success);
    instr_pct = safe_pct(instr_success, total_success);

    % Figure: combinations (free)
    f1 = figure('Visible','off','Position',[50 50 700 500]);
    create_combination_plot(sum_free_LL, sum_free_LR, sum_free_RL, sum_free_RR, 'Free Choice', free_success, free_pct);
    p1 = fullfile(out_dir, [base_name '_free_combinations.png']);
    exportgraphics(f1, p1, 'Resolution', 200);
    close(f1);
    plot_paths{end+1,1} = p1;

    % Figure: combinations (instructed)
    f2 = figure('Visible','off','Position',[50 50 700 500]);
    create_combination_plot(sum_instr_LL, sum_instr_LR, sum_instr_RL, sum_instr_RR, 'Instructed', instr_success, instr_pct);
    p2 = fullfile(out_dir, [base_name '_instructed_combinations.png']);
    exportgraphics(f2, p2, 'Resolution', 200);
    close(f2);
    plot_paths{end+1,1} = p2;

    % Figure: ipsi vs contra
    f3 = figure('Visible','off','Position',[50 50 700 500]);
    create_ipsi_contra_plot(sum_free_LL, sum_free_LR, sum_free_RL, sum_free_RR, sum_instr_LL, sum_instr_LR, sum_instr_RL, sum_instr_RR);
    p3 = fullfile(out_dir, [base_name '_ipsi_contra.png']);
    exportgraphics(f3, p3, 'Resolution', 200);
    close(f3);
    plot_paths{end+1,1} = p3;

    % Plots are saved as PNG files in the output directory
    % No Excel sheet is created for plots

function plot_paths = make_delay_duration_plots(trials_tbl, out_dir, base_name)
    % Create logistic regression plots for delay duration vs success
    % Input: trials_tbl - table with DelayDuration and Success columns
    % Output: plot_paths - cell array of plot file paths
    
    plot_paths = {};
    
    % Extract delay duration and success data (exclude NaN delays)
    valid_idx = ~isnan(trials_tbl.DelayDuration);
    delay_durations = trials_tbl.DelayDuration(valid_idx);
    success = double(trials_tbl.Success(valid_idx));  % Ensure numeric 0/1
    
    if sum(valid_idx) < 10  % Need at least 10 data points for meaningful analysis
        return;  % Not enough data
    end
    
    % Check if we have variation in success (need both 0s and 1s for logistic regression)
    if all(success == 0) || all(success == 1)
        % Create simple histogram plot plus time-until-abort histogram
        fig = figure('Visible','off','Position',[50 50 1200 500]);
        subplot(1, 2, 1);
        histogram(delay_durations, 20, 'FaceColor', [0.5 0.5 0.5], 'EdgeColor', 'black');
        xlabel('Delay Duration (s)', 'FontWeight', 'bold');
        ylabel('Number of Trials', 'FontWeight', 'bold');
        if all(success == 1)
            status_str = 'successful';
        else
            status_str = 'failed';
        end
        title(sprintf('Delay Duration Distribution: %s\n(All trials %s)', base_name, status_str), ...
            'FontSize', 12, 'FontWeight', 'bold');
        grid on;
        subplot(1, 2, 2);
        idx_abort_del = contains(lower(string(trials_tbl.reason_of_abort)), 'abort_hnd_del_per_state') & ~isnan(trials_tbl.TimeUntilAbort);
        time_until_abort = trials_tbl.TimeUntilAbort(idx_abort_del);
        if ~isempty(time_until_abort)
            histogram(time_until_abort, 20, 'FaceColor', [0.8 0.4 0.2], 'EdgeColor', 'black');
            xlabel('Time until abort (s)', 'FontWeight', 'bold');
            ylabel('Number of trials', 'FontWeight', 'bold');
            title(sprintf('Time until abort (abort\\_hnd\\_del\\_per\\_state)\nn = %d', numel(time_until_abort)), 'FontSize', 12, 'FontWeight', 'bold');
            grid on;
        else
            text(0.5, 0.5, 'No abort\_hnd\_del\_per\_state trials', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
        end
        plot_path = fullfile(out_dir, [base_name '_delay_duration_histogram.png']);
        exportgraphics(fig, plot_path, 'Resolution', 200);
        close(fig);
        plot_paths{end+1,1} = plot_path;
        return;
    end
    
    % Perform logistic regression
    try
        % Fit logistic regression model: logit(P(success)) = b0 + b1*delay_duration
        % Using glmfit with binomial distribution
        [b, dev, stats] = glmfit(delay_durations, success, 'binomial', 'link', 'logit');
        
        % Create smooth curve for plotting
        delay_range = linspace(min(delay_durations), max(delay_durations), 200);
        logit_pred = b(1) + b(2) * delay_range;
        prob_pred = 1 ./ (1 + exp(-logit_pred));  % Inverse logit
        
        % Create figure with multiple subplots (2x3 to add time-until-abort histogram)
        fig = figure('Visible','off','Position',[50 50 1400 1000]);
        
        % Subplot 1: Logistic regression curve with data points
        subplot(2, 3, 1);
        scatter(delay_durations, success, 50, 'filled', 'MarkerFaceAlpha', 0.6);
        hold on;
        plot(delay_range, prob_pred, 'r-', 'LineWidth', 2);
        xlabel('Delay Duration (s)', 'FontWeight', 'bold');
        ylabel('Success Probability', 'FontWeight', 'bold');
        title(sprintf('Logistic Regression: Delay Duration vs Success\nβ₀=%.3f, β₁=%.3f (p=%.4f)', ...
            b(1), b(2), stats.p(2)), 'FontSize', 12, 'FontWeight', 'bold');
        legend('Data', 'Logistic Fit', 'Location', 'best');
        grid on;
        ylim([-0.1 1.1]);
        
        % Subplot 2: Delay duration distributions for successful vs failed trials
        subplot(2, 3, 2);
        success_delays = delay_durations(success == 1);
        fail_delays = delay_durations(success == 0);
        if ~isempty(success_delays) && ~isempty(fail_delays)
            histogram(success_delays, 'FaceColor', [0 0.8 0], 'FaceAlpha', 0.6, 'EdgeColor', 'black');
            hold on;
            histogram(fail_delays, 'FaceColor', [0.8 0 0], 'FaceAlpha', 0.6, 'EdgeColor', 'black');
            xlabel('Delay Duration (s)', 'FontWeight', 'bold');
            ylabel('Number of Trials', 'FontWeight', 'bold');
            title('Delay Duration Distribution', 'FontSize', 12, 'FontWeight', 'bold');
            legend(sprintf('Success (n=%d)', length(success_delays)), ...
                   sprintf('Failed (n=%d)', length(fail_delays)), 'Location', 'best');
            grid on;
        end
        
        % Subplot 3: Success rate by delay duration bins
        subplot(2, 3, 3);
        n_bins = 10;
        bin_edges = linspace(min(delay_durations), max(delay_durations), n_bins+1);
        bin_centers = (bin_edges(1:end-1) + bin_edges(2:end)) / 2;
        success_rate = zeros(n_bins, 1);
        bin_counts = zeros(n_bins, 1);
        for i = 1:n_bins
            bin_idx = delay_durations >= bin_edges(i) & delay_durations < bin_edges(i+1);
            if i == n_bins  % Include right edge for last bin
                bin_idx = delay_durations >= bin_edges(i) & delay_durations <= bin_edges(i+1);
            end
            if sum(bin_idx) > 0
                success_rate(i) = mean(success(bin_idx));
                bin_counts(i) = sum(bin_idx);
            else
                success_rate(i) = NaN;
            end
        end
        valid_bins = ~isnan(success_rate);
        bar(bin_centers(valid_bins), success_rate(valid_bins), 'FaceColor', [0.2 0.6 0.8]);
        hold on;
        plot(delay_range, prob_pred, 'r-', 'LineWidth', 2);
        xlabel('Delay Duration (s)', 'FontWeight', 'bold');
        ylabel('Success Rate', 'FontWeight', 'bold');
        title('Success Rate by Delay Duration Bins', 'FontSize', 12, 'FontWeight', 'bold');
        legend('Binned Success Rate', 'Logistic Fit', 'Location', 'best');
        grid on;
        ylim([0 1]);
        
        % Subplot 4: Summary statistics
        subplot(2, 3, 4);
        axis off;
        stats_text = sprintf('LOGISTIC REGRESSION SUMMARY\n');
        stats_text = [stats_text sprintf('========================\n\n')];
        stats_text = [stats_text sprintf('Total trials with delay: %d\n', length(delay_durations))];
        stats_text = [stats_text sprintf('Successful: %d (%.1f%%)\n', sum(success), mean(success)*100)];
        stats_text = [stats_text sprintf('Failed: %d (%.1f%%)\n\n', sum(~success), mean(~success)*100)];
        stats_text = [stats_text sprintf('Delay Duration Statistics:\n')];
        stats_text = [stats_text sprintf('  Mean: %.3f s\n', mean(delay_durations))];
        stats_text = [stats_text sprintf('  Median: %.3f s\n', median(delay_durations))];
        stats_text = [stats_text sprintf('  Range: [%.3f, %.3f] s\n\n', min(delay_durations), max(delay_durations))];
        stats_text = [stats_text sprintf('Logistic Regression:\n')];
        stats_text = [stats_text sprintf('  Intercept (β₀): %.3f (p=%.4f)\n', b(1), stats.p(1))];
        stats_text = [stats_text sprintf('  Slope (β₁): %.3f (p=%.4f)\n', b(2), stats.p(2))];
        stats_text = [stats_text sprintf('  Deviance: %.2f\n', dev)];
        if stats.p(2) < 0.05
            stats_text = [stats_text sprintf('  Significance: ** p < 0.05\n')];
        elseif stats.p(2) < 0.01
            stats_text = [stats_text sprintf('  Significance: *** p < 0.01\n')];
        else
            stats_text = [stats_text sprintf('  Significance: ns (p >= 0.05)\n')];
        end
        text(0.1, 0.5, stats_text, 'FontSize', 10, ...
             'VerticalAlignment', 'middle', 'HorizontalAlignment', 'left');
        
        % Subplot 5: Histogram of time until abort for abort_hnd_del_per_state failures
        subplot(2, 3, 5);
        idx_abort_del = contains(lower(string(trials_tbl.reason_of_abort)), 'abort_hnd_del_per_state') & ~isnan(trials_tbl.TimeUntilAbort);
        time_until_abort = trials_tbl.TimeUntilAbort(idx_abort_del);
        if ~isempty(time_until_abort)
            histogram(time_until_abort, 20, 'FaceColor', [0.8 0.4 0.2], 'EdgeColor', 'black');
            xlabel('Time until abort (s)', 'FontWeight', 'bold');
            ylabel('Number of trials', 'FontWeight', 'bold');
            title(sprintf('Time until abort (abort\\_hnd\\_del\\_per\\_state)\nn = %d', numel(time_until_abort)), 'FontSize', 12, 'FontWeight', 'bold');
            grid on;
        else
            text(0.5, 0.5, 'No abort\_hnd\_del\_per\_state trials', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
        end
        
        sgtitle(sprintf('Delay Duration Analysis: %s', base_name), 'FontSize', 14, 'FontWeight', 'bold');
        
        % Save plot
        plot_path = fullfile(out_dir, [base_name '_delay_duration_logistic.png']);
        try
            exportgraphics(fig, plot_path, 'Resolution', 200);
        catch
            % Fallback for older MATLAB versions
            print(fig, plot_path, '-dpng', '-r200');
        end
        close(fig);
        plot_paths{end+1,1} = plot_path;
        
    catch ME
        warning('Could not perform logistic regression: %s', ME.message);
        % Create a simple histogram plot as fallback
        try
            fig = figure('Visible','off','Position',[50 50 1000 600]);
            success_delays = delay_durations(success == 1);
            fail_delays = delay_durations(success == 0);
            if ~isempty(success_delays) && ~isempty(fail_delays)
                histogram(success_delays, 'FaceColor', [0 0.8 0], 'FaceAlpha', 0.6, 'EdgeColor', 'black');
                hold on;
                histogram(fail_delays, 'FaceColor', [0.8 0 0], 'FaceAlpha', 0.6, 'EdgeColor', 'black');
                xlabel('Delay Duration (s)', 'FontWeight', 'bold');
                ylabel('Number of Trials', 'FontWeight', 'bold');
                title(sprintf('Delay Duration Distribution: %s\n(Logistic regression failed)', base_name), ...
                    'FontSize', 12, 'FontWeight', 'bold');
                legend(sprintf('Success (n=%d)', length(success_delays)), ...
                       sprintf('Failed (n=%d)', length(fail_delays)), 'Location', 'best');
                grid on;
            end
            plot_path = fullfile(out_dir, [base_name '_delay_duration_histogram.png']);
            try
                exportgraphics(fig, plot_path, 'Resolution', 200);
            catch
                print(fig, plot_path, '-dpng', '-r200');
            end
            close(fig);
            plot_paths{end+1,1} = plot_path;
        catch
            % Skip if plotting fails
        end
    end

function plot_paths = make_target_acquisition_plots(trials_tbl, out_dir, base_name)
    % Same analysis as Delay Duration but for hand movement time (delay end → target hold). Save as image.
    plot_paths = {};
    valid_idx = ~isnan(trials_tbl.TargetAcqTime);
    target_acq_times = trials_tbl.TargetAcqTime(valid_idx);
    success = double(trials_tbl.Success(valid_idx));
    
    if sum(valid_idx) < 10
        return;
    end
    
    if all(success == 0) || all(success == 1)
        fig = figure('Visible','off','Position',[50 50 1000 600]);
        histogram(target_acq_times, 20, 'FaceColor', [0.5 0.5 0.5], 'EdgeColor', 'black');
        xlabel('Hand movement time (s)', 'FontWeight', 'bold');
        ylabel('Number of Trials', 'FontWeight', 'bold');
        status_str = 'failed';
        if all(success == 1)
            status_str = 'successful';
        end
        title(sprintf('Hand movement time (delay end \\rightarrow target hold): %s\n(All trials %s)', base_name, status_str), 'FontSize', 12, 'FontWeight', 'bold');
        grid on;
        plot_path = fullfile(out_dir, [base_name '_target_acquisition_time_histogram.png']);
        exportgraphics(fig, plot_path, 'Resolution', 200);
        close(fig);
        plot_paths{end+1,1} = plot_path;
        return;
    end
    
    try
        [b, dev, stats] = glmfit(target_acq_times, success, 'binomial', 'link', 'logit');
        time_range = linspace(min(target_acq_times), max(target_acq_times), 200);
        logit_pred = b(1) + b(2) * time_range;
        prob_pred = 1 ./ (1 + exp(-logit_pred));
        
        fig = figure('Visible','off','Position',[50 50 1400 1000]);
        
        subplot(2, 2, 1);
        scatter(target_acq_times, success, 50, 'filled', 'MarkerFaceAlpha', 0.6);
        hold on;
        plot(time_range, prob_pred, 'r-', 'LineWidth', 2);
        xlabel('Hand movement time (s)', 'FontWeight', 'bold');
        ylabel('Success Probability', 'FontWeight', 'bold');
        title(sprintf('Logistic Regression: Hand movement time vs Success\nβ₀=%.3f, β₁=%.3f (p=%.4f)', b(1), b(2), stats.p(2)), 'FontSize', 12, 'FontWeight', 'bold');
        legend('Data', 'Logistic Fit', 'Location', 'best');
        grid on;
        ylim([-0.1 1.1]);
        
        subplot(2, 2, 2);
        success_times = target_acq_times(success == 1);
        fail_times = target_acq_times(success == 0);
        if ~isempty(success_times) && ~isempty(fail_times)
            histogram(success_times, 'FaceColor', [0 0.8 0], 'FaceAlpha', 0.6, 'EdgeColor', 'black');
            hold on;
            histogram(fail_times, 'FaceColor', [0.8 0 0], 'FaceAlpha', 0.6, 'EdgeColor', 'black');
            xlabel('Hand movement time (s)', 'FontWeight', 'bold');
            ylabel('Number of Trials', 'FontWeight', 'bold');
            title('Hand movement time distribution', 'FontSize', 12, 'FontWeight', 'bold');
            legend(sprintf('Success (n=%d)', length(success_times)), sprintf('Failed (n=%d)', length(fail_times)), 'Location', 'best');
            grid on;
        end
        
        subplot(2, 2, 3);
        n_bins = 10;
        bin_edges = linspace(min(target_acq_times), max(target_acq_times), n_bins+1);
        bin_centers = (bin_edges(1:end-1) + bin_edges(2:end)) / 2;
        success_rate = zeros(n_bins, 1);
        for i = 1:n_bins
            bin_idx = target_acq_times >= bin_edges(i) & target_acq_times < bin_edges(i+1);
            if i == n_bins
                bin_idx = target_acq_times >= bin_edges(i) & target_acq_times <= bin_edges(i+1);
            end
            if sum(bin_idx) > 0
                success_rate(i) = mean(success(bin_idx));
            else
                success_rate(i) = NaN;
            end
        end
        valid_bins = ~isnan(success_rate);
        bar(bin_centers(valid_bins), success_rate(valid_bins), 'FaceColor', [0.2 0.6 0.8]);
        hold on;
        plot(time_range, prob_pred, 'r-', 'LineWidth', 2);
        xlabel('Hand movement time (s)', 'FontWeight', 'bold');
        ylabel('Success Rate', 'FontWeight', 'bold');
        title('Success Rate by Hand movement time Bins', 'FontSize', 12, 'FontWeight', 'bold');
        legend('Binned Success Rate', 'Logistic Fit', 'Location', 'best');
        grid on;
        ylim([0 1]);
        
        subplot(2, 2, 4);
        axis off;
        stats_text = sprintf('HAND MOVEMENT TIME SUMMARY\n(delay end \\rightarrow target hold)\n');
        stats_text = [stats_text sprintf('====================================\n\n')];
        stats_text = [stats_text sprintf('Total trials with movement time: %d\n', length(target_acq_times))];
        stats_text = [stats_text sprintf('Successful: %d (%.1f%%)\n', sum(success), mean(success)*100)];
        stats_text = [stats_text sprintf('Failed: %d (%.1f%%)\n\n', sum(~success), mean(~success)*100)];
        stats_text = [stats_text sprintf('Hand movement time Statistics:\n')];
        stats_text = [stats_text sprintf('  Mean: %.3f s\n', mean(target_acq_times))];
        stats_text = [stats_text sprintf('  Median: %.3f s\n', median(target_acq_times))];
        stats_text = [stats_text sprintf('  Range: [%.3f, %.3f] s\n\n', min(target_acq_times), max(target_acq_times))];
        stats_text = [stats_text sprintf('Logistic Regression:\n')];
        stats_text = [stats_text sprintf('  Intercept (β₀): %.3f (p=%.4f)\n', b(1), stats.p(1))];
        stats_text = [stats_text sprintf('  Slope (β₁): %.3f (p=%.4f)\n', b(2), stats.p(2))];
        stats_text = [stats_text sprintf('  Deviance: %.2f\n', dev)];
        if stats.p(2) < 0.05
            stats_text = [stats_text sprintf('  Significance: ** p < 0.05\n')];
        elseif stats.p(2) < 0.01
            stats_text = [stats_text sprintf('  Significance: *** p < 0.01\n')];
        else
            stats_text = [stats_text sprintf('  Significance: ns (p >= 0.05)\n')];
        end
        text(0.1, 0.5, stats_text, 'FontSize', 10, 'VerticalAlignment', 'middle', 'HorizontalAlignment', 'left');
        
        sgtitle(sprintf('Hand movement time Analysis (delay end \\rightarrow target hold): %s', base_name), 'FontSize', 14, 'FontWeight', 'bold');
        plot_path = fullfile(out_dir, [base_name '_target_acquisition_time_logistic.png']);
        try
            exportgraphics(fig, plot_path, 'Resolution', 200);
        catch
            print(fig, plot_path, '-dpng', '-r200');
        end
        close(fig);
        plot_paths{end+1,1} = plot_path;
    catch ME
        warning('Could not perform target acquisition time analysis: %s', ME.message);
    end

function write_tables_to_excel(excel_path, before_tbl, after_tbl, before_trials_tbl, after_trials_tbl)
    % Overwrite existing file
    if exist(excel_path, 'file')
        delete(excel_path);
    end

    % Write general parameter tables
    writetable(before_tbl, excel_path, 'Sheet', 'before_general');
    writetable(after_tbl,  excel_path, 'Sheet', 'after_general');
    
    % Write trial-by-trial detailed tables with formatting
    writetable(before_trials_tbl, excel_path, 'Sheet', 'before_all_data');
    writetable(after_trials_tbl,  excel_path, 'Sheet', 'after_all_data');
    
    % Apply formatting: red for failed trials, green for successful trials
    try
        % Open Excel file for formatting
        excel = actxserver('Excel.Application');
        excel.Visible = 0;
        workbook = excel.Workbooks.Open(excel_path);
        
        % Format before_all_data sheet
        format_trial_sheet(workbook, 'before_all_data', before_trials_tbl);
        
        % Format after_all_data sheet
        format_trial_sheet(workbook, 'after_all_data', after_trials_tbl);
        
        % Save and close
        workbook.Save();
        workbook.Close();
        excel.Quit();
        delete(excel);
    catch ME
        % If COM automation fails, just write tables without formatting
        warning('Could not apply Excel formatting: %s', ME.message);
    end

function format_trial_sheet(workbook, sheet_name, tbl)
    % Format trial sheet: red for failed, green for successful
    try
        sheet = workbook.Worksheets.Item(sheet_name);
        
        % Find Success column index
        success_col_idx = find(strcmp(tbl.Properties.VariableNames, 'Success'), 1);
        if isempty(success_col_idx)
            return;
        end
        
        % Get used range
        used_range = sheet.UsedRange;
        if isempty(used_range)
            return;
        end
        
        n_rows = used_range.Rows.Count;
        if n_rows < 2  % Header + at least one data row
            return;
        end
        
        % Format rows based on Success column
        % Excel uses BGR color format (Blue-Green-Red), not RGB
        for i = 2:n_rows  % Skip header row
            success_val = sheet.Cells.Item(i, success_col_idx).Value;
            if ~isempty(success_val) && isnumeric(success_val)
                if success_val == 0  % Failed - Red background
                    % Set entire row to red background (BGR: 0000FF = RGB: FF0000)
                    row_range = sheet.Range(sheet.Cells.Item(i, 1), sheet.Cells.Item(i, used_range.Columns.Count));
                    row_range.Interior.Color = 255;  % Red in BGR (low byte = red)
                    row_range.Font.Color = 16777215;  % White text (FFFFFF in BGR)
                elseif success_val == 1  % Success - Green background
                    % Set entire row to green background (BGR: 00FF00 = RGB: 00FF00)
                    row_range = sheet.Range(sheet.Cells.Item(i, 1), sheet.Cells.Item(i, used_range.Columns.Count));
                    row_range.Interior.Color = 65280;  % Green in BGR (middle byte = green)
                    row_range.Font.Color = 0;  % Black text
                end
            end
        end
        
        % Auto-fit columns
        used_range.Columns.AutoFit;
        
    catch ME
        warning('Could not format sheet %s: %s', sheet_name, ME.message);
    end

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
    % X-axis order: L-H/L-T, R-H/L-T, L-H/R-T, R-H/R-T
    data = [LL, RL, LR, RR];
    colors = [0.2, 0.6, 0.8; 0.4, 1.0, 0.8; 0.4, 0.8, 1.0; 0.2, 0.8, 0.6];
    labels = {'L-H/L-T', 'R-H/L-T', 'L-H/R-T', 'R-H/R-T'};
    
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