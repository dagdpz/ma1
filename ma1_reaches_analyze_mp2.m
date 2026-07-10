function details = ma1_reaches_analyze_mp2(input_path, animal_name, session_date)
% ma1_reaches_analyze_mp2 - Daily reach analysis with per-block and day-summary plots.
%
% Timing metrics (successful trials only), two independent epochs:
%   FIXATION: RTFixToSensorRelease, MTSensorToFixHold
%   REACH:    RTGoToMovement (Go -> fixation detach), MTMovementToTarget (detach -> target)
%
% - Automatically detects all blocks (runs) from *.mat files in the day folder.
% - Eye-calibration-only runs/trials (effector eye, no hand) are excluded.
% - Generates one figure per block and one day-summary figure.
% - Exports Excel with per-block and day-summary sheets.
% - Output path: Y:\Data\{animal_name}\{animal_name}_{yyyy-mm-dd}\
%
% Usage:
%   details = ma1_reaches_analyze_mp2('/path/to/one_run.mat', 'monkey_name');
%   details = ma1_reaches_analyze_mp2('/path/to/day_folder', 'monkey_name');
%   Session date is auto-detected from run filenames or folder name unless provided.

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

    % Collect all run files for the day (skip eye-calibration-only blocks)
    all_run_files = list_day_runs(input_path);
    run_files = filter_calibration_runs(all_run_files);
    if isempty(run_files)
        error('No hand-reach .mat files found for the day (only eye-calibration runs detected).');
    end

    if nargin < 3 || isempty(session_date)
        session_date = infer_session_date(input_path, run_files);
    end

    n_blocks = numel(run_files);

    out_dir = ensure_output_dir(animal_name, session_date);
    date_str = datestr(session_date, 'yyyy-mm-dd');
    excel_filename = sprintf('%s_%s.xlsx', animal_name, date_str);
    excel_fullpath = fullfile(out_dir, excel_filename);

    block_tbls = cell(n_blocks, 1);
    block_trials_tbls = cell(n_blocks, 1);
    block_plot_paths = cell(n_blocks, 1);

    for k = 1:n_blocks
        block_label = sprintf('Block%d', k);
        block_tbls{k} = analyze_runs_to_table(run_files(k), block_label);
        block_trials_tbls{k} = analyze_runs_to_trial_table(run_files(k), block_label);
        base_name = sprintf('%s_%s_block%d', animal_name, date_str, k);
        block_plot_paths{k} = [ ...
            make_block_analysis_figure(block_trials_tbls{k}, block_tbls{k}, out_dir, base_name); ...
            make_free_choice_timing_figure(block_trials_tbls{k}, block_tbls{k}, out_dir, base_name)];
    end

    day_tbl = analyze_runs_to_table(run_files, 'Day');
    day_trials_tbl = analyze_runs_to_trial_table(run_files, 'Day');
    day_base = sprintf('%s_%s_day', animal_name, date_str);
    day_plot_paths = [ ...
        make_block_analysis_figure(day_trials_tbl, day_tbl, out_dir, day_base); ...
        make_free_choice_timing_figure(day_trials_tbl, day_tbl, out_dir, day_base)];

    all_plot_paths = day_plot_paths;
    for k = 1:n_blocks
        all_plot_paths = [all_plot_paths; block_plot_paths{k}]; %#ok<AGROW>
    end

    write_tables_to_excel(excel_fullpath, block_tbls, block_trials_tbls, day_tbl, day_trials_tbl);

    details = struct();
    details.animal_name = animal_name;
    details.session_date = session_date;
    details.run_files = run_files;
    details.n_blocks = n_blocks;
    if numel(all_run_files) > numel(run_files)
        details.skipped_calibration_runs = setdiff(all_run_files, run_files);
    else
        details.skipped_calibration_runs = {};
    end
    details.excel_fullpath = excel_fullpath;
    details.out_dir = out_dir;
    details.plot_files = all_plot_paths;
    details.block_tables = block_tbls;
    details.day_table = day_tbl;
    details.block_trials_tables = block_trials_tbls;
    details.day_trials_table = day_trials_tbl;
    
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
    % Prefer animal prefix from run filenames: {Animal}{YYYY-MM-DD}_{NN}.mat
    % e.g. Fen2026-01-16_01.mat -> Fen. Falls back to folder name if parsing fails.
    run_files = list_day_runs(input_path);
    if ~isempty(run_files)
        parsed_names = cell(size(run_files));
        for k = 1:numel(run_files)
            parsed_names{k} = parse_animal_from_run_filename(run_files{k});
        end
        parsed_names = parsed_names(~cellfun('isempty', parsed_names));
        if ~isempty(parsed_names)
            animal_name = parsed_names{1};
            return;
        end
    end

    if isfolder(input_path)
        [~, animal_name] = fileparts(input_path);
        return;
    end
    [parent_path, ~, ~] = fileparts(input_path);
    [~, animal_name] = fileparts(parent_path);

function animal_name = parse_animal_from_run_filename(run_file)
    % Extract animal prefix before session date in run filename.
    animal_name = '';
    if isempty(run_file)
        return;
    end
    [~, stem, ~] = fileparts(run_file);
    tokens = regexp(stem, '^(.+?)(\d{4}-\d{2}-\d{2})_\d+$', 'tokens', 'once');
    if isempty(tokens)
        return;
    end
    animal_name = strtrim(tokens{1});

function session_date = infer_session_date(input_path, run_files)
    % Session date from run filenames (Fen2026-01-16_01.mat) or folder (20260116).
    session_date = NaT;
    if nargin >= 2 && ~isempty(run_files)
        for k = 1:numel(run_files)
            session_date = parse_session_date_from_run_filename(run_files{k});
            if ~isnat(session_date)
                return;
            end
        end
    end
    session_date = parse_session_date_from_path(input_path);
    if isnat(session_date)
        session_date = datetime('today');
    end

function session_date = parse_session_date_from_run_filename(run_file)
    session_date = NaT;
    if isempty(run_file)
        return;
    end
    [~, stem, ~] = fileparts(run_file);
    tokens = regexp(stem, '(\d{4}-\d{2}-\d{2})_\d+$', 'tokens', 'once');
    if isempty(tokens)
        return;
    end
    session_date = datetime(tokens{1}, 'InputFormat', 'yyyy-MM-dd');

function session_date = parse_session_date_from_path(input_path)
    % Folder names like 20260116 -> 2026-01-16.
    session_date = NaT;
    if isempty(input_path)
        return;
    end
    if isfolder(input_path)
        folder_name = char(input_path);
    else
        folder_name = fileparts(input_path);
    end
    [~, name, ~] = fileparts(folder_name);
    tokens = regexp(name, '^(\d{8})$', 'tokens', 'once');
    if isempty(tokens)
        return;
    end
    ymd = tokens{1};
    session_date = datetime(str2double(ymd(1:4)), str2double(ymd(5:6)), str2double(ymd(7:8)));

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

function run_files = filter_calibration_runs(run_files)
    % Drop run files that contain only eye-calibration trials (no hand task).
    if isempty(run_files)
        return;
    end
    keep = false(size(run_files));
    for k = 1:numel(run_files)
        keep(k) = ~is_calibration_run_file(run_files{k});
    end
    run_files = run_files(keep);

function tf = is_calibration_run_file(filepath)
    % True when every trial in the run is an eye-calibration task.
    tf = false;
    if isempty(filepath) || ~isfile(filepath)
        return;
    end
    data = load(filepath);
    if ~isfield(data, 'trial') || isempty(data.trial)
        return;
    end
    trials = data.trial;
    tf = true;
    for i = 1:numel(trials)
        if ~is_eye_calibration_trial(trials(i))
            tf = false;
            return;
        end
    end

function trials = filter_reach_trials(trials)
    % Keep only hand-reach trials; drop eye-calibration trials if mixed into a run.
    if isempty(trials)
        return;
    end
    keep = false(numel(trials), 1);
    for i = 1:numel(trials)
        keep(i) = ~is_eye_calibration_trial(trials(i));
    end
    trials = trials(keep);

function tf = is_eye_calibration_trial(trial)
    % Eye-calibration task: hands are not used (effector eye / task type calibration).
    tf = false;
    if isempty(trial) || ~isstruct(trial)
        return;
    end
    effector = get_scalar_num_field(trial, 'effector');
    if ~isnan(effector) && effector == 0
        tf = true;
        return;
    end
    trial_type = get_scalar_num_field(trial, 'type');
    if ~isnan(trial_type) && trial_type == 1
        tf = true;
    end

function tbl = empty_trial_table()
    tbl = table( ...
        string([]), int32([]), int32([]), string([]), ...
        string([]), double([]), double([]), double([]), double([]), double([]), double([]), ...
        string([]), string([]), double([]), string([]), double([]), ...
        'VariableNames', {'Condition', 'Run', 'Trial', 'File', 'TaskType', 'DelayDuration', 'TargetAcqTime', ...
        'RTFixToSensorRelease', 'MTSensorToFixHold', 'RTGoToMovement', 'MTMovementToTarget', ...
        'Target', 'Hand', 'Success', 'reason_of_abort', 'TimeUntilAbort'});

function run_tbl = empty_run_summary_table(condition_label, run_index, filepath)
    run_tbl = table( ...
        string(condition_label), run_index, string(filepath), string(""), 0, 0, 0, 0, ...
        NaN, NaN, NaN, ...
        0, 0, 0, 0, ...
        0, 0, 0, 0, ...
        0, 0, 0, 0, ...
        0, 0, NaN, ...
        0, 0, NaN, ...
        0, 0, NaN, ...
        0, 0, NaN, ...
        0, 0, 0, 0, 0, ...
        'VariableNames', { ...
            'Condition','Run','File','ReachParadigm','AllTrials','InitiatedTrials','SuccessfulTrials','FailedTrials', ...
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

function out_dir = ensure_output_dir(animal_name, session_date)
    % Output root: Y:\Data\{animal_name}\{animal_name}_{yyyy-mm-dd}\
    data_root = fullfile('Y:', 'Data');
    animal_dir = fullfile(data_root, animal_name);
    if ~exist(animal_dir, 'dir')
        mkdir(animal_dir);
    end
    session_folder = sprintf('%s_%s', animal_name, datestr(session_date, 'yyyy-mm-dd'));
    out_dir = fullfile(animal_dir, session_folder);
    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end

function run_files = normalize_run_files(run_files)
    if iscell(run_files)
        if numel(run_files) == 1 && iscell(run_files{1})
            run_files = run_files{1};
        end
        return;
    end
    if isstring(run_files)
        run_files = cellstr(run_files);
        return;
    end
    if ischar(run_files)
        run_files = {run_files};
    end

function tbl = analyze_runs_to_table(run_files, condition_label)
    run_files = normalize_run_files(run_files);
    n = numel(run_files);
    rows = cell(n, 1);
    for k = 1:n
        rows{k} = analyze_single_run(run_files{k}, k, condition_label);
    end
    tbl = vertcat(rows{:});

function tbl = analyze_runs_to_trial_table(run_files, condition_label)
    % Create a detailed trial-by-trial table with delay duration and success status
    run_files = normalize_run_files(run_files);
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
            string([]), double([]), double([]), double([]), double([]), double([]), double([]), ...
            string([]), string([]), double([]), string([]), double([]), ...
            'VariableNames', {'Condition', 'Run', 'Trial', 'File', 'TaskType', 'DelayDuration', 'TargetAcqTime', ...
            'RTFixToSensorRelease', 'MTSensorToFixHold', 'RTGoToMovement', 'MTMovementToTarget', ...
            'Target', 'Hand', 'Success', 'reason_of_abort', 'TimeUntilAbort'});
    else
        % Remove empty tables
        non_empty = ~cellfun(@isempty, all_trial_tables);
        if any(non_empty)
            tbl = vertcat(all_trial_tables{non_empty});
        else
            tbl = table( ...
                string([]), int32([]), int32([]), string([]), ...
                string([]), double([]), double([]), double([]), double([]), double([]), double([]), ...
                string([]), string([]), double([]), string([]), double([]), ...
                'VariableNames', {'Condition', 'Run', 'Trial', 'File', 'TaskType', 'DelayDuration', 'TargetAcqTime', ...
            'RTFixToSensorRelease', 'MTSensorToFixHold', 'RTGoToMovement', 'MTMovementToTarget', ...
            'Target', 'Hand', 'Success', 'reason_of_abort', 'TimeUntilAbort'});
        end
    end

function trial_rows = analyze_single_run_trials(filepath, run_index, condition_label)
    % Extract trial-by-trial data including delay duration, success, task type, target, hand, abort reason
    data = load(filepath);
    if ~isfield(data, 'trial')
        error('File does not contain variable "trial": %s', filepath);
    end
    trials = filter_reach_trials(data.trial);
    
    n_trials = length(trials);
    if n_trials == 0
        trial_rows = empty_trial_table();
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
    rt_fix_sensor_col = NaN(n_trials, 1);
    mt_sensor_fix_col = NaN(n_trials, 1);
    rt_go_move_col = NaN(n_trials, 1);
    mt_move_target_col = NaN(n_trials, 1);
    target_col = repmat(string(""), n_trials, 1);
    hand_col = repmat(string(""), n_trials, 1);
    success_col = zeros(n_trials, 1);
    abort_reason_col = repmat(string(""), n_trials, 1);
    time_until_abort_col = NaN(n_trials, 1);
    
    for i = 1:n_trials
        trial = trials(i);
        
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
        
        % Extract success status before timing metrics (RT/MT only for successful trials)
        if isfield(trial, 'success') && ~isempty(trial.success)
            success_col(i) = double(trial.success(1));
        end

        if success_col(i) == 1
            [rt_fix_sensor_col(i), mt_sensor_fix_col(i), rt_go_move_col(i), mt_move_target_col(i)] = ...
                get_trial_timing_metrics(trial);
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
        
        % Extract abort reason (if trial failed) - convert to lowercase
        if success_col(i) == 0
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
        rt_fix_sensor_col, ...
        mt_sensor_fix_col, ...
        rt_go_move_col, ...
        mt_move_target_col, ...
        target_col, ...
        hand_col, ...
        success_col, ...
        abort_reason_col, ...
        time_until_abort_col, ...
        'VariableNames', {'Condition', 'Run', 'Trial', 'File', 'TaskType', 'DelayDuration', 'TargetAcqTime', ...
        'RTFixToSensorRelease', 'MTSensorToFixHold', 'RTGoToMovement', 'MTMovementToTarget', ...
        'Target', 'Hand', 'Success', 'reason_of_abort', 'TimeUntilAbort'});

function run_tbl = analyze_single_run(filepath, run_index, condition_label)
    data = load(filepath);
    if ~isfield(data, 'trial')
        error('File does not contain variable "trial": %s', filepath);
    end
    trials = filter_reach_trials(data.trial);
    reach_paradigm = get_reach_paradigm_type(data, trials);
    if isempty(trials)
        run_tbl = empty_run_summary_table(condition_label, run_index, filepath);
        run_tbl.ReachParadigm(:) = reach_paradigm;
        return;
    end

    % Basic counts
    all_trials = length(trials);
    successful_trials = sum([trials.success] == 1);
    failed_trials = sum([trials.success] == 0);
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
        string(condition_label), run_index, string(filepath), reach_paradigm, all_trials, initiated_trials, successful_trials, failed_trials, ...
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
            'Condition','Run','File','ReachParadigm','AllTrials','InitiatedTrials','SuccessfulTrials','FailedTrials', ...
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

function pct = safe_pct(x, n)
    if n > 0
        pct = x / n * 100;
    else
        pct = NaN;
    end

function paradigm = get_reach_paradigm_type(data, trials)
    % Block-level reach paradigm label for general summary tables.
    paradigm = "";
    if isfield(data, 'task')
        paradigm = effector_to_paradigm_label(get_scalar_num_field(data.task, 'effector'));
    end
    if paradigm == ""
        effectors = [];
        for i = 1:numel(trials)
            eff = get_scalar_num_field(trials(i), 'effector');
            if ~isnan(eff)
                effectors(end + 1) = eff; %#ok<AGROW>
            end
        end
        if ~isempty(effectors)
            paradigm = effector_to_paradigm_label(mode(effectors));
        end
    end
    if paradigm == ""
        paradigm = "unknown";
    end

function paradigm = effector_to_paradigm_label(effector)
    % Map MonkeyPsych effector code to analysis label.
    paradigm = "";
    if isnan(effector)
        return;
    end
    if ismember(effector, [1, 6])
        paradigm = "direct reaches";
    elseif effector == 4
        paradigm = "dissociated reaches";
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
    candidate_fields = {'delay_success','delaySuccess','delay_outcome','delayOutcome','delay'};
    for i = 1:numel(candidate_fields)
        fn = candidate_fields{i};
        if isfield(tr, fn)
            val = tr.(fn);
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
    end

function f = get_aborted_flag(tr)
    % Returns 1 if trial is marked as aborted in any reasonable field, else 0.
    f = 0;
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
    candidate_fields = {'abort_code','abortCode','abort_reason','abortReason','aborted_reason', ...
                        'error','error_code','errorCode','fail_reason','failReason'};
    for i = 1:numel(candidate_fields)
        fn = candidate_fields{i};
        if isfield(tr, fn)
            val = tr.(fn);
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
    end

function [rt_fix_sensor, mt_sensor_fix, rt_go_move, mt_move_target] = get_trial_timing_metrics(trial)
    % Trial timing on successful trials only. Two independent stimulus->response epochs:
    %
    % FIXATION EPOCH
    %   RTFixToSensorRelease : FIX_ACQ(2) onset -> reach-hand sensor release
    %   MTSensorToFixHold    : sensor release -> FIX_HOL(3) onset
    %
    % REACH EPOCH (reaction to Go cue)
    %   RTGoToMovement       : Go cue TAR_ACQ(4) -> on-screen fixation detach (fix exit)
    %   MTMovementToTarget   : speed-based movement onset -> TAR_HOL(5)
    %
    rt_fix_sensor = get_rt_fix_to_sensor_release(trial);
    mt_sensor_fix = get_mt_sensor_to_fix_hold(trial);
    [rt_go_move, mt_move_target] = get_reach_epoch_timing(trial);

function rt_fix = get_rt_fix_to_sensor_release(trial)
    % Latency: fixation acquired -> release of home sensor (fixation epoch, not Go).
    rt_fix = NaN;
    cfg = get_timing_detection_config();
    t_fix_acq = get_fix_acq_onset(trial);
    t_fix_hol = get_state_event_onset(trial, 3);
    t_release = get_sensor_release_time(trial, t_fix_acq, t_fix_hol);
    if ~isnan(t_fix_acq) && ~isnan(t_release)
        rt_fix = sanitize_latency(t_release - t_fix_acq, cfg.min_rt_fix, cfg.max_rt_fix);
    end

function mt_fix = get_mt_sensor_to_fix_hold(trial)
    % Movement time: sensor release -> fixation hold onset (fixation epoch).
    mt_fix = NaN;
    cfg = get_timing_detection_config();
    t_fix_acq = get_fix_acq_onset(trial);
    t_fix_hol = get_state_event_onset(trial, 3);
    t_release = get_sensor_release_time(trial, t_fix_acq, t_fix_hol);
    if ~isnan(t_release) && ~isnan(t_fix_hol)
        mt_fix = sanitize_latency(t_fix_hol - t_release, cfg.min_mt_fix, cfg.max_mt_fix);
    end

function [rt_go, mt_target] = get_reach_epoch_timing(trial)
    % Reach epoch: Go -> fixation detach (RT); movement onset -> target (MT).
    rt_go = NaN;
    mt_target = NaN;
    cfg = get_timing_detection_config();
    t_go = get_go_cue_onset(trial);
    if isnan(t_go)
        return;
    end
    % RT: unchanged — exit from on-screen fixation after Go.
    t_detach = get_fixation_detach_time(trial, t_go);
    if isnan(t_detach)
        return;
    end
    rt_go = sanitize_latency(t_detach - t_go, cfg.min_rt_go, cfg.max_rt_go);
    if isnan(rt_go)
        return;
    end
    % MT: separate onset (speed burst at fixation), not the RT anchor.
    t_mt_start = detect_speed_onset_near_fixation(trial, t_go, cfg);
    if isnan(t_mt_start)
        t_mt_start = t_detach;
    end
    mt_target = get_mt_movement_to_target(trial, t_mt_start);

function mt_target = get_mt_movement_to_target(trial, t_move_start)
    % Movement time: reach movement onset -> target hold.
    mt_target = NaN;
    if isnan(t_move_start)
        return;
    end
    t_target = get_target_hold_onset_time(trial, t_move_start);
    if isnan(t_target)
        return;
    end
    cfg = get_timing_detection_config();
    mt_target = sanitize_latency(t_target - t_move_start, cfg.min_mt_target, cfg.max_mt_target);

function cfg = get_timing_detection_config()
    % Bounds for fixation-epoch latencies.
    cfg.min_rt_fix = 0.05;
    cfg.max_rt_fix = 5.0;
    cfg.min_mt_fix = 0.01;
    cfg.max_mt_fix = 5.0;
    % Bounds for RT to target (Go cue -> screen fixation exit).
    cfg.min_rt_go = 0.05;
    cfg.max_rt_go = 2.0;
    % RT: Go cue -> fixation exit (fix_exit_radius). MT uses separate speed onset.
    cfg.pre_go_baseline_win = 0.10;
    cfg.fix_exit_radius = 1.2;   % leave fixation point on screen (~1 unit tolerance)
    cfg.move_onset_speed_abs = 400;
    cfg.move_onset_speed_margin = 150;
    cfg.move_onset_max_disp = 2.0;  % MT start: speed burst while still at fixation
    cfg.min_mt_target = 0.10;  % physiologically plausible minimum (~100 ms)
    cfg.max_mt_target = 2.0;
    % Target arrival detector (kinematic hold zone, not state-5 event time).
    cfg.target_hold_window = 0.05;
    cfg.target_acq_radius = 5;
    cfg.target_sustain_samples = 3;

function val = sanitize_latency(val, min_val, max_val)
    if isnan(val) || val < min_val || val > max_val
        val = NaN;
    end

function t_fix_acq = get_fix_acq_onset(trial)
    % Last FIX_ACQ(2) event before TAR_ACQ(4).
    t_fix_acq = NaN;
    if ~isfield(trial, 'states') || ~isfield(trial, 'states_onset')
        return;
    end
    states = trial.states(:);
    onsets = trial.states_onset(:);
    idx_tar = find(states == 4, 1, 'first');
    if isempty(idx_tar)
        idx_fix = find(states == 2);
    else
        idx_fix = find(states == 2 & (1:numel(states))' < idx_tar);
    end
    if ~isempty(idx_fix)
        t_fix_acq = onsets(idx_fix(end));
    end

function t_go = get_go_cue_onset(trial)
    % Go cue: first TAR_ACQ(4) event onset.
    t_go = get_state_event_onset(trial, 4);

function t_on = get_state_event_onset(trial, state_code)
    t_on = NaN;
    if ~isfield(trial, 'states') || ~isfield(trial, 'states_onset')
        return;
    end
    states = trial.states(:);
    onsets = trial.states_onset(:);
    idx = find(states == state_code, 1, 'first');
    if ~isempty(idx) && idx <= numel(onsets)
        t_on = onsets(idx);
    end

function t_release = get_sensor_release_time(trial, t_after, t_before)
    % First reach-hand sensor release after t_after (and before t_before if given).
    t_release = NaN;
    if nargin < 2 || isempty(t_after) || isnan(t_after)
        t_after = -inf;
    end
    if nargin < 3
        t_before = NaN;
    end
    if ~isfield(trial, 'reach_hand') || ~isfield(trial, 'tSample_from_time_start')
        return;
    end
    rh = get_scalar_num_field(trial, 'reach_hand');
    if rh == 1
        if ~isfield(trial, 'sen_L')
            return;
        end
        sen = trial.sen_L(:);
    elseif rh == 2
        if ~isfield(trial, 'sen_R')
            return;
        end
        sen = trial.sen_R(:);
    else
        return;
    end
    t = trial.tSample_from_time_start(:);
    if numel(sen) < 2 || numel(t) < 2
        return;
    end
    n = min(numel(sen), numel(t));
    sen = sen(1:n);
    t = t(1:n);
    t = align_tsample_to_state_time(trial, t);
    rel_candidates = find(sen(1:end-1) > 0.5 & sen(2:end) <= 0.5);
    for k = 1:numel(rel_candidates)
        rel_idx = rel_candidates(k);
        t_rel = t(rel_idx + 1);
        if t_rel >= t_after && (isnan(t_before) || t_rel <= t_before)
            t_release = t_rel;
            return;
        end
    end

function t_aligned = align_tsample_to_state_time(trial, t)
    % Express tSample on the same scale/origin as states_onset.
    t_aligned = t(:);
    if ~isfield(trial, 'states_onset') || isempty(trial.states_onset) || numel(t_aligned) < 2
        return;
    end
    state_t = trial.states_onset(:);
    state_t = state_t(~isnan(state_t));
    if isempty(state_t)
        return;
    end

    max_state = max(state_t);
    max_t = max(t_aligned);

    % Only rescale when one stream is clearly in seconds and the other in ms.
    if max_state > 100 && max_t > 0 && max_t <= 60
        t_aligned = t_aligned * 1000;
    elseif max_state > 0 && max_state <= 60 && max_t > 100
        t_aligned = t_aligned / 1000;
    end

    offset = NaN;
    if isfield(trial, 'states') && isfield(trial, 'state') && ~isempty(trial.state)
        state_events = trial.states(:);
        event_onsets = trial.states_onset(:);
        state_samples = trial.state(:);
        n_samp = min(numel(t_aligned), numel(state_samples));
        anchor_codes = [4, 2, 3, 5];
        for code = anchor_codes
            idx_evt = find(state_events == code, 1, 'first');
            idx_samp = find(state_samples(1:n_samp) == code, 1, 'first');
            if ~isempty(idx_evt) && ~isempty(idx_samp) && idx_evt <= numel(event_onsets)
                offset = event_onsets(idx_evt) - t_aligned(idx_samp);
                break;
            end
        end
    end

    if isnan(offset)
        offset = state_t(1) - t_aligned(1);
    end
    if abs(offset) > 1e-6
        t_aligned = t_aligned + offset;
    end

function [t, x, y, state] = get_aligned_hand_kinematics(trial)
    t = trial.tSample_from_time_start(:);
    x = trial.x_hnd(:);
    y = trial.y_hnd(:);
    state = [];
    if isfield(trial, 'state') && ~isempty(trial.state)
        state = trial.state(:);
    end
    n = min([numel(t), numel(x), numel(y)]);
    if ~isempty(state)
        n = min(n, numel(state));
    end
    t = align_tsample_to_state_time(trial, t(1:n));
    x = x(1:n);
    y = y(1:n);
    if ~isempty(state)
        state = state(1:n);
    end
    valid = ~isnan(x) & ~isnan(y) & ~isnan(t);
    t = t(valid);
    x = x(valid);
    y = y(valid);
    if ~isempty(state)
        state = state(valid);
    end

function [t, x, y, speed] = get_hand_speed_profile(trial)
    [t, x, y, ~] = get_aligned_hand_kinematics(trial);
    speed = [];
    if numel(t) < 2
        return;
    end
    dt = diff(t);
    speed = sqrt(diff(x).^2 + diff(y).^2) ./ max(dt, eps);

function [xh, yh] = get_target_hold_position(trial)
    % Target hold zone center from kinematics (not state-5 event time).
    xh = NaN;
    yh = NaN;
    cfg = get_timing_detection_config();
    [t, x, y, state] = get_aligned_hand_kinematics(trial);
    if isempty(t)
        return;
    end

    hold_mask = [];
    if ~isempty(state)
        hold_mask = state == 5;
    end
    if any(hold_mask)
        t_hold = t(hold_mask);
        final_mask = hold_mask & t >= (max(t_hold) - cfg.target_hold_window);
        if ~any(final_mask)
            final_mask = hold_mask;
        end
    else
        final_mask = t >= (max(t) - cfg.target_hold_window);
    end

    if ~any(final_mask)
        return;
    end
    xh = median(x(final_mask));
    yh = median(y(final_mask));

function t_detach = get_fixation_detach_time(trial, t_go)
    % Hand detach from on-screen fixation after Go (RT endpoint).
    t_detach = NaN;
    if ~isfield(trial, 'x_hnd') || ~isfield(trial, 'y_hnd') || ~isfield(trial, 'tSample_from_time_start')
        return;
    end
    if isnan(t_go)
        return;
    end
    t_detach = detect_fixation_detach_after_go(trial, t_go, get_timing_detection_config());

function t_move = get_movement_initiation_time(trial, t_go)
    % Backward-compatible alias for fixation detach time.
    t_move = get_fixation_detach_time(trial, t_go);

function t_on = detect_speed_onset_near_fixation(trial, t_go, cfg)
    % First high-velocity sample while hand is still at screen fixation (MT start).
    t_on = NaN;
    [t, x, y, ~] = get_aligned_hand_kinematics(trial);
    if numel(t) < 4 || isnan(t_go)
        return;
    end

    spd = zeros(numel(t), 1);
    for j = 2:numel(t)
        dt = max(t(j) - t(j - 1), eps);
        spd(j) = hypot(x(j) - x(j - 1), y(j) - y(j - 1)) / dt;
    end

    pre_mask = t >= (t_go - cfg.pre_go_baseline_win) & t < t_go;
    if ~any(pre_mask)
        return;
    end
    x0 = median(x(pre_mask));
    y0 = median(y(pre_mask));
    dist = hypot(x - x0, y - y0);
    base_spd = median(spd(pre_mask));
    speed_thr = max(cfg.move_onset_speed_abs, base_spd + cfg.move_onset_speed_margin);

    t_earliest = t_go + cfg.min_rt_go;
    t_latest = t_go + cfg.max_rt_go;
    t_tar_hol = get_state_event_onset(trial, 5);
    if ~isnan(t_tar_hol)
        t_latest = min(t_latest, t_tar_hol);
    end

    idx = find(t >= t_earliest & t <= t_latest & ...
        spd >= speed_thr & dist < cfg.move_onset_max_disp, 1, 'first');
    if ~isempty(idx)
        t_on = t(idx);
    end

function t_detach = detect_fixation_detach_after_go(trial, t_go, cfg)
    % First on-screen fixation detach/movement after Go (RT endpoint).
    t_detach = NaN;
    [t, x, y, ~] = get_aligned_hand_kinematics(trial);
    if numel(t) < 3 || isnan(t_go)
        return;
    end

    pre_mask = t >= (t_go - cfg.pre_go_baseline_win) & t < t_go;
    if ~any(pre_mask)
        return;
    end
    x0 = median(x(pre_mask));
    y0 = median(y(pre_mask));

    t_earliest = t_go + cfg.min_rt_go;
    t_latest = t_go + cfg.max_rt_go;
    t_tar_hol = get_state_event_onset(trial, 5);
    if ~isnan(t_tar_hol)
        t_latest = min(t_latest, t_tar_hol);
    end

    idx = find(t >= t_earliest & t <= t_latest & ...
        hypot(x - x0, y - y0) >= cfg.fix_exit_radius, 1, 'first');
    if ~isempty(idx)
        t_detach = t(idx);
    end

function t_target = get_target_hold_onset_time(trial, t_detach)
    % Target hold onset for MT (search begins at detach, inclusive).
    t_target = NaN;
    if isnan(t_detach)
        return;
    end

    t_tar_hol = get_state_event_onset(trial, 5);
    if ~isnan(t_tar_hol) && t_tar_hol >= t_detach
        t_target = t_tar_hol;
        return;
    end

    t_target = get_kinematic_target_arrival_time(trial, t_detach);

function t_target = get_kinematic_target_arrival_time(trial, t_detach)
    % Kinematic target arrival at/after detach (fallback when state 5 is missing).
    t_target = NaN;
    if isnan(t_detach) || ~isfield(trial, 'x_hnd') || ~isfield(trial, 'y_hnd')
        return;
    end

    cfg = get_timing_detection_config();
    [xh, yh] = get_target_hold_position(trial);
    if isnan(xh) || isnan(yh)
        return;
    end

    [t, x, y, ~] = get_aligned_hand_kinematics(trial);
    onset_idx = find(t >= t_detach, 1, 'first');
    if isempty(onset_idx)
        return;
    end

    n_sustain = cfg.target_sustain_samples;
    for k = onset_idx:(numel(t) - n_sustain + 1)
        in_zone = hypot(x(k:(k + n_sustain - 1)) - xh, y(k:(k + n_sustain - 1)) - yh) <= cfg.target_acq_radius;
        if all(in_zone)
            t_target = t(k);
            return;
        end
    end

function plot_paths = make_block_analysis_figure(trials_tbl, summary_tbl, out_dir, base_name)
    % Combined figure: free/instructed combinations and ipsi/contra choice counts.
    plot_paths = {};
    if isempty(summary_tbl)
        return;
    end

    [combo_labels, combo_keys, combo_colors] = get_hand_target_plot_config();
    counts = aggregate_combination_counts(summary_tbl);

    fig = figure('Visible', 'off', 'Position', [50 50 1600 550]);

    subplot(1, 3, 1);
    plot_combination_bars(counts.free_LL, counts.free_LR, counts.free_RL, counts.free_RR, ...
        combo_labels, combo_colors, 'Free Choice');

    subplot(1, 3, 2);
    plot_combination_bars(counts.instr_LL, counts.instr_LR, counts.instr_RL, counts.instr_RR, ...
        combo_labels, combo_colors, 'Instructed');

    subplot(1, 3, 3);
    plot_ipsi_contra_bars(counts.free_LL, counts.free_LR, counts.free_RL, counts.free_RR, ...
        counts.instr_LL, counts.instr_LR, counts.instr_RL, counts.instr_RR);

    sgtitle(sprintf('Reach Analysis: %s', base_name), 'FontSize', 14, 'FontWeight', 'bold');

    plot_path = fullfile(out_dir, [base_name '.png']);
    try
        exportgraphics(fig, plot_path, 'Resolution', 200);
    catch
        print(fig, plot_path, '-dpng', '-r200');
    end
    close(fig);
    plot_paths{end+1, 1} = plot_path;

function counts = aggregate_combination_counts(summary_tbl)
    counts = struct();
    counts.free_LL = nansum(summary_tbl.Free_LL);
    counts.free_LR = nansum(summary_tbl.Free_LR);
    counts.free_RL = nansum(summary_tbl.Free_RL);
    counts.free_RR = nansum(summary_tbl.Free_RR);
    counts.instr_LL = nansum(summary_tbl.Instr_LL);
    counts.instr_LR = nansum(summary_tbl.Instr_LR);
    counts.instr_RL = nansum(summary_tbl.Instr_RL);
    counts.instr_RR = nansum(summary_tbl.Instr_RR);

function [combo_labels, combo_keys, combo_colors] = get_hand_target_plot_config()
    color_left_hand = [0.4, 0.8, 1.0];   % blue
    color_right_hand = [0.2, 0.8, 0.4];  % green
    combo_labels = { ...
        'Left hand – left target', ...
        'Left hand – right target', ...
        'Right hand – left target', ...
        'Right hand – right target'};
    combo_keys = {'Left|Left', 'Left|Right', 'Right|Left', 'Right|Right'};
    combo_colors = [ ...
        color_left_hand; ...
        min(color_left_hand + 0.15, 1); ...
        min(color_right_hand + 0.15, 1); ...
        color_right_hand];

function plot_combination_bars(LL, LR, RL, RR, labels, colors, title_str)
    data = [LL, LR, RL, RR];
    if sum(data) == 0
        text(0.5, 0.5, 'No data available', 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', 'FontWeight', 'bold');
        axis off;
        title(title_str, 'FontSize', 11, 'FontWeight', 'bold');
        return;
    end

    x = 1:4;
    bh = bar(x, data, 0.65, 'FaceColor', 'flat');
    for i = 1:4
        bh.CData(i, :) = colors(i, :);
    end
    hold on;
    total = sum(data);
    for i = 1:4
        if data(i) > 0
            pct = data(i) / total * 100;
            text(x(i), data(i), sprintf('%d\n(%.1f%%)', data(i), pct), ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
                'FontWeight', 'bold', 'FontSize', 9);
        end
    end
    set(gca, 'XTick', x, 'XTickLabel', labels, 'FontWeight', 'bold');
    xtickangle(20);
    ylabel('Number of trials', 'FontWeight', 'bold');
    title(sprintf('%s\n(n = %d)', title_str, total), 'FontSize', 11, 'FontWeight', 'bold');
    grid on;

function plot_ipsi_contra_bars(free_LL, free_LR, free_RL, free_RR, instr_LL, instr_LR, instr_RL, instr_RR)
    color_ipsi = [1.0, 1.0, 0.0];      % yellow
    color_contra = [0.9, 0.2, 0.2];    % red
    task_labels = {'Free Choice', 'Instructed'};
    data = [free_LL + free_RR, free_LR + free_RL; instr_LL + instr_RR, instr_LR + instr_RL];

    x = 1:2;
    hold on;
    bh1 = bar(x - 0.18, data(:, 1), 0.34, 'FaceColor', color_ipsi, 'EdgeColor', 'k');
    bh2 = bar(x + 0.18, data(:, 2), 0.34, 'FaceColor', color_contra, 'EdgeColor', 'k');
    set(gca, 'XTick', x, 'XTickLabel', task_labels, 'FontWeight', 'bold');
    ylabel('Number of trials', 'FontWeight', 'bold');
    title('Ipsilateral vs Contralateral Choice', 'FontSize', 11, 'FontWeight', 'bold');
    legend([bh1, bh2], {'Ipsilateral', 'Contralateral'}, 'Location', 'best');
    grid on;

    for i = 1:2
        row_total = sum(data(i, :));
        for j = 1:2
            if data(i, j) > 0 && row_total > 0
                pct = data(i, j) / row_total * 100;
                x_pos = i + (j - 1.5) * 0.18;
                text(x_pos, data(i, j), sprintf('%d\n(%.1f%%)', data(i, j), pct), ...
                    'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
                    'FontWeight', 'bold', 'FontSize', 9);
            end
        end
    end

function plot_go_reaction_timeline(trials_tbl, combo_keys, combo_labels, combo_colors)
    % trials_tbl: successful free-choice trials with complete RT/MT metrics.
    if isempty(trials_tbl) || height(trials_tbl) == 0
        text(0.5, 0.5, 'No successful free-choice trials', 'HorizontalAlignment', 'center');
        axis off;
        return;
    end

    sorted_tbl = sortrows(trials_tbl, {'Run', 'Trial'});
    n_trials = height(sorted_tbl);
    if n_trials < 1
        text(0.5, 0.5, 'No free-choice trials', 'HorizontalAlignment', 'center');
        axis off;
        return;
    end

    trial_idx = (1:n_trials)';
    hold on;
    legend_entries = {};
    for g = 1:numel(combo_keys)
        parts = split(combo_keys{g}, '|');
        combo_mask = sorted_tbl.Hand == parts{1} & sorted_tbl.Target == parts{2};
        if ~any(combo_mask)
            continue;
        end
        combo_trials = trial_idx(combo_mask);
        combo_rts = sorted_tbl.RTGoToMovement(combo_mask);
        plot(combo_trials, combo_rts, '-o', 'LineWidth', 1.8, ...
            'Color', combo_colors(g, :), 'MarkerFaceColor', combo_colors(g, :), ...
            'MarkerSize', 4);
        legend_entries{end+1} = combo_labels{g}; %#ok<AGROW>
    end

    xlabel('Trial', 'FontWeight', 'bold');
    ylabel('RT to target (s)', 'FontWeight', 'bold');
    title('RT to Target Over Trials (Go \rightarrow Fix Exit)', 'FontSize', 11, 'FontWeight', 'bold');
    xlim([0.5, n_trials + 0.5]);
    grid on;
    if ~isempty(legend_entries)
        legend(legend_entries, 'Location', 'best');
    else
        text(0.5, 0.5, 'No successful free-choice Go RT data', ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
    end

function plot_paths = make_free_choice_timing_figure(trials_tbl, summary_tbl, out_dir, base_name)
    % Timing figure: fixation-epoch latencies, Go reaction time, movement time, success rates.
    plot_paths = {};
    if isempty(trials_tbl) || height(trials_tbl) == 0
        return;
    end

    [combo_labels, combo_keys, combo_colors] = get_hand_target_plot_config();
    color_left_hand = combo_colors(1, :);
    color_right_hand = combo_colors(4, :);

    free_tbl = trials_tbl(trials_tbl.TaskType == "Free", :);
    if isempty(free_tbl)
        return;
    end

    success_free = free_tbl(free_tbl.Success == 1, :);
    % Use the same successful free-choice cohort on all RT/MT panels.
    success_free = subset_trials_with_complete_timing(success_free);
    if isempty(success_free)
        return;
    end

    fig = figure('Visible', 'off', 'Position', [50 50 1600 1000]);

    subplot(2, 3, 1);
    groups_hand = ["Left", "Right"];
    [means, sems, ns] = mean_sem_by_group(success_free, 'Hand', 'RTFixToSensorRelease', groups_hand);
    trial_pts = collect_trial_values_by_group(success_free, 'Hand', groups_hand, 'RTFixToSensorRelease');
    plot_hand_bar(means, sems, ns, {'Left hand', 'Right hand'}, ...
        [color_left_hand; color_right_hand], 'RT: Fixation \rightarrow Sensor Release', 'Time (s)', trial_pts);

    subplot(2, 3, 2);
    [means, sems, ns] = mean_sem_by_group(success_free, 'Hand', 'MTSensorToFixHold', groups_hand);
    trial_pts = collect_trial_values_by_group(success_free, 'Hand', groups_hand, 'MTSensorToFixHold');
    plot_hand_bar(means, sems, ns, {'Left hand', 'Right hand'}, ...
        [color_left_hand; color_right_hand], 'MT: Sensor Release \rightarrow Fix Hold', 'Time (s)', trial_pts);

    subplot(2, 3, 3);
    [means, sems, ns] = mean_sem_by_combo(success_free, combo_keys, 'RTGoToMovement');
    trial_pts = collect_trial_values_by_combo(success_free, combo_keys, 'RTGoToMovement');
    plot_hand_bar(means, sems, ns, combo_labels, combo_colors, 'RT to Target (Go \rightarrow Fix Exit)', 'Time (s)', trial_pts);

    subplot(2, 3, 4);
    [means, sems, ns] = mean_sem_by_combo(success_free, combo_keys, 'MTMovementToTarget');
    trial_pts = collect_trial_values_by_combo(success_free, combo_keys, 'MTMovementToTarget');
    plot_hand_bar(means, sems, ns, combo_labels, combo_colors, 'MT: Fix Exit \rightarrow Target', 'Time (s)', trial_pts);

    subplot(2, 3, 5);
    plot_go_reaction_timeline(success_free, combo_keys, combo_labels, combo_colors);

    subplot(2, 3, 6);
    plot_instructed_vs_choice_success(summary_tbl, color_left_hand, color_right_hand);

    sgtitle(sprintf('Timing Analysis (Free Choice): %s', base_name), ...
        'FontSize', 14, 'FontWeight', 'bold');

    plot_path = fullfile(out_dir, [base_name '_free_choice_timing.png']);
    try
        exportgraphics(fig, plot_path, 'Resolution', 200);
    catch
        print(fig, plot_path, '-dpng', '-r200');
    end
    close(fig);
    plot_paths{end+1, 1} = plot_path;

function timing_fields = get_timing_metric_fields()
    timing_fields = {'RTFixToSensorRelease', 'MTSensorToFixHold', ...
        'RTGoToMovement', 'MTMovementToTarget'};

function mask = complete_timing_mask(tbl)
    % True for trials with all RT/MT metrics available.
    mask = true(height(tbl), 1);
    if isempty(tbl)
        return;
    end
    timing_fields = get_timing_metric_fields();
    for k = 1:numel(timing_fields)
        mask = mask & ~isnan(tbl.(timing_fields{k}));
    end

function tbl = subset_trials_with_complete_timing(tbl)
    tbl = tbl(complete_timing_mask(tbl), :);

function [means, sems, ns] = mean_sem_by_group(tbl, group_field, value_field, groups)
    n_groups = numel(groups);
    means = nan(n_groups, 1);
    sems = nan(n_groups, 1);
    ns = zeros(n_groups, 1);
    for g = 1:n_groups
        idx = tbl.(group_field) == groups(g) & tbl.Success == 1 & ~isnan(tbl.(value_field));
        vals = tbl.(value_field)(idx);
        ns(g) = numel(vals);
        if ns(g) > 0
            means(g) = mean(vals);
            if ns(g) > 1
                sems(g) = std(vals) / sqrt(ns(g));
            else
                sems(g) = 0;
            end
        end
    end

function [means, sems, ns] = mean_sem_by_combo(tbl, combo_keys, value_field)
    n_groups = numel(combo_keys);
    means = nan(n_groups, 1);
    sems = nan(n_groups, 1);
    ns = zeros(n_groups, 1);
    for g = 1:n_groups
        parts = split(combo_keys{g}, '|');
        idx = tbl.Hand == parts{1} & tbl.Target == parts{2} & tbl.Success == 1 & ~isnan(tbl.(value_field));
        vals = tbl.(value_field)(idx);
        ns(g) = numel(vals);
        if ns(g) > 0
            means(g) = mean(vals);
            if ns(g) > 1
                sems(g) = std(vals) / sqrt(ns(g));
            else
                sems(g) = 0;
            end
        end
    end

function trial_points = collect_trial_values_by_group(tbl, group_field, groups, value_field)
    trial_points = cell(numel(groups), 1);
    for g = 1:numel(groups)
        idx = tbl.(group_field) == groups(g) & tbl.Success == 1 & ~isnan(tbl.(value_field));
        trial_points{g} = tbl.(value_field)(idx);
    end

function trial_points = collect_trial_values_by_combo(tbl, combo_keys, value_field)
    trial_points = cell(numel(combo_keys), 1);
    for g = 1:numel(combo_keys)
        parts = split(combo_keys{g}, '|');
        idx = tbl.Hand == parts{1} & tbl.Target == parts{2} & tbl.Success == 1 & ~isnan(tbl.(value_field));
        trial_points{g} = tbl.(value_field)(idx);
    end

function plot_hand_bar(means, sems, ns, labels, colors, title_str, y_label, trial_points)
    if nargin < 8
        trial_points = {};
    end
    x = 1:numel(means);
    bh = bar(x, means, 0.65, 'FaceColor', 'flat');
    for i = 1:numel(means)
        if i <= size(colors, 1)
            bh.CData(i, :) = colors(i, :);
        end
    end
    hold on;
    errorbar(x, means, sems, 'k.', 'LineWidth', 1.2, 'CapSize', 8);
    overlay_trial_points_on_bars(x, trial_points, colors);
    set(gca, 'XTick', x, 'XTickLabel', labels, 'FontWeight', 'bold');
    xtickangle(20);
    ylabel(y_label, 'FontWeight', 'bold');
    title(title_str, 'FontSize', 11, 'FontWeight', 'bold');
    grid on;
    ymax = max(means + sems, [], 'omitnan');
    if ~isempty(trial_points)
        all_pts = vertcat(trial_points{:});
        if ~isempty(all_pts)
            ymax = max([ymax; all_pts], [], 'omitnan');
        end
    end
    if ~isempty(ymax) && ~isnan(ymax)
        ylim([0, ymax * 1.12]);
    end
    for i = 1:numel(means)
        if ~isnan(means(i))
            text(x(i), means(i) + sems(i), sprintf('n=%d', ns(i)), ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
                'FontSize', 8, 'FontWeight', 'bold');
        end
    end

function overlay_trial_points_on_bars(x, trial_points, colors)
    % Round markers for each trial value, jittered within each bar group.
    if isempty(trial_points)
        return;
    end
    n_groups = numel(x);
    for g = 1:min(n_groups, numel(trial_points))
        vals = trial_points{g}(:);
        vals = vals(~isnan(vals));
        if isempty(vals)
            continue;
        end
        n_pts = numel(vals);
        if n_pts == 1
            x_pts = x(g);
        else
            x_pts = x(g) + linspace(-0.18, 0.18, n_pts);
        end
        pt_color = colors(min(g, size(colors, 1)), :);
        scatter(x_pts, vals, 20, 'o', ...
            'MarkerFaceColor', pt_color, ...
            'MarkerEdgeColor', [0.15, 0.15, 0.15], ...
            'LineWidth', 0.6, ...
            'MarkerFaceAlpha', 0.9);
    end

function plot_instructed_vs_choice_success(summary_tbl, color_left_hand, color_right_hand)
    if isempty(summary_tbl)
        text(0.5, 0.5, 'No summary data available', 'HorizontalAlignment', 'center');
        axis off;
        return;
    end

    instr_left = safe_pct(nansum(summary_tbl.InstrLeftSuccess), nansum(summary_tbl.InstrLeftTotal));
    free_left = safe_pct(nansum(summary_tbl.FreeLeftSuccess), nansum(summary_tbl.FreeLeftTotal));
    instr_right = safe_pct(nansum(summary_tbl.InstrRightSuccess), nansum(summary_tbl.InstrRightTotal));
    free_right = safe_pct(nansum(summary_tbl.FreeRightSuccess), nansum(summary_tbl.FreeRightTotal));

    x = [1 2];
    % Grouped bar: rows = hand groups (Left/Right), columns = series (Instructed/Choice).
    y = [instr_left, free_left; instr_right, free_right];
    bh = bar(x, y, 'grouped', 'EdgeColor', 'k');
    bh(1).FaceColor = 'flat';
    bh(1).CData = [color_left_hand; color_right_hand];
    bh(1).FaceAlpha = 0.45;
    bh(2).FaceColor = 'flat';
    bh(2).CData = [color_left_hand; color_right_hand];
    bh(2).FaceAlpha = 0.95;

    set(gca, 'XTick', x, 'XTickLabel', {'Left hand', 'Right hand'}, 'FontWeight', 'bold');
    ylabel('Success rate (%)', 'FontWeight', 'bold');
    title('Success Rate (Instructed vs Choice)', 'FontSize', 11, 'FontWeight', 'bold');
    ylim([0 100]);
    grid on;
    legend(bh, {'Instructed', 'Choice'}, 'Location', 'best');

    for s = 1:2
        vals = y(:, s);
        xpos = bh(s).XEndPoints;
        for k = 1:2
            if ~isnan(vals(k))
                text(xpos(k), vals(k) + 2, sprintf('%.1f%%', vals(k)), ...
                    'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
                    'FontSize', 9, 'FontWeight', 'bold');
            end
        end
    end

function write_tables_to_excel(excel_path, block_tbls, block_trials_tbls, day_tbl, day_trials_tbl)
    if exist(excel_path, 'file')
        delete(excel_path);
    end

    writetable(day_tbl, excel_path, 'Sheet', 'day_general');
    writetable(day_trials_tbl, excel_path, 'Sheet', 'day_all_data');

    n_blocks = numel(block_tbls);
    for k = 1:n_blocks
        sheet_general = sprintf('block%d_general', k);
        sheet_data = sprintf('block%d_all_data', k);
        writetable(block_tbls{k}, excel_path, 'Sheet', sheet_general);
        writetable(block_trials_tbls{k}, excel_path, 'Sheet', sheet_data);
    end

    try
        excel = actxserver('Excel.Application');
        excel.Visible = 0;
        workbook = excel.Workbooks.Open(excel_path);

        format_trial_sheet(workbook, 'day_all_data', day_trials_tbl);
        for k = 1:n_blocks
            format_trial_sheet(workbook, sprintf('block%d_all_data', k), block_trials_tbls{k});
        end

        workbook.Save();
        workbook.Close();
        excel.Quit();
        delete(excel);
    catch ME
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

