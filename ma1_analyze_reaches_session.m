function out = ma1_analyze_reaches_session(input_path, output_base, skip_runs, write_excel)
% ma1_analyze_reaches_session - Daily hand-reach session analysis (tables, plots, Excel).
%
% Pipeline: setup -> resolve out_dir -> discover runs -> one-load analyze -> day tables
%           -> 3x4 PDF figures (per-run + session) -> optional Excel -> out struct.
%
% Timing metrics (successful trials only):
%   FIXATION: RTFixToSensorRelease, MTSensorToFixHold
%   REACH:    RTGoToMovement (Go -> fixation detach), MTMovementToTarget (detach -> target)
%
% Target L/R is fix-relative (tar.x vs fix.x), not screen hemifield.
% Uncrossed = LL/RR; Crossed = LR/RL.
%
% Usage:
%   out = ma1_analyze_reaches_session(input_path, output_base);
%   out = ma1_analyze_reaches_session(input_path, output_base, skip_runs);
%   out = ma1_analyze_reaches_session(input_path, output_base, skip_runs, write_excel);
%   out = ma1_analyze_reaches_session(input_path, output_base, false);  % no Excel
%
% Example:
%   out = ma1_analyze_reaches_session( ...
%       'Y:\Data\Feno\20260715', ...
%       'Y:\Projects\dPul-MIP\Feno\Behavior_analysis\', false);
%   % PDFs in Y:\Projects\dPul-MIP\Feno\Behavior_analysis\20260715
%   % e.g. Fen2026-07-15_02.pdf , Feno_2026-07-15_session.pdf
%
% Inputs:
%   input_path   - day folder OR a single .mat (only that file if a file)
%   output_base  - analysis root; session leaf from input_path -> out_dir
%   skip_runs    - optional basenames and/or 1-based indices (or logical write_excel)
%   write_excel  - optional logical, default true
%
% Output (struct out): animal_name, session_date, session_folder, output_base, out_dir,
%   run_files, n_runs, skipped_calibration_runs, skipped_user_runs, write_excel,
%   excel_fullpath, plot_files, run_tables, day_table, run_trials_tables, day_trials_table
%
% Figures (tiledlayout 3x4): row1 instr success / free-choice share / uncrossed;
%   row2 four RT/MT panels; row3 RT-vs-trial + wait-from-cue hist (tiles 11-12 spare).
% DelayForHist is ALWAYS from CUE_ON onset (success = cue+delay; abort = cue→abort).
% Panel 2 = instructed hand×space only (Free success-by-chosen-space omitted).

    prevWarn = warning('query', 'MATLAB:xlswrite:AddSheet');
    warning('off', 'MATLAB:xlswrite:AddSheet');
    c = onCleanup(@() warning(prevWarn)); %#ok<NASGU>

    run(fullfile(fileparts(mfilename('fullpath')), 'ma1_task_state_dictionary.m'));

    if nargin < 1 || isempty(input_path)
        error('Input path is required (file or folder).');
    end
    if nargin < 2 || isempty(output_base)
        error('Output base path is required.');
    end
    if nargin < 3 || isempty(skip_runs)
        skip_runs = {};
    end
    if nargin < 4 || isempty(write_excel)
        write_excel = true;
    end
    if nargin == 3 && islogical(skip_runs) && isscalar(skip_runs)
        write_excel = skip_runs;
        skip_runs = {};
    end
    if ~islogical(write_excel) || ~isscalar(write_excel)
        error('write_excel must be a scalar logical.');
    end

    session_folder = infer_session_folder_name(input_path);
    out_dir = ensure_output_dir(fullfile(char(output_base), session_folder));
    animal_name = infer_animal_name(input_path);

    all_run_files = list_day_runs(input_path);
    fprintf('\n=== Run discovery ===\n');
    fprintf('Input: %s\n', char(input_path));
    fprintf('Found %d .mat file(s):\n', numel(all_run_files));
    for i = 1:numel(all_run_files)
        fprintf('  [%d] %s\n', i, all_run_files{i});
    end

    [run_candidates, skipped_user_runs] = apply_skip_runs(all_run_files, skip_runs);
    if ~isempty(skipped_user_runs)
        fprintf('Skipped by user skip_runs (%d):\n', numel(skipped_user_runs));
        for i = 1:numel(skipped_user_runs)
            fprintf('  - %s\n', skipped_user_runs{i});
        end
    end
    fprintf('Candidates after skip_runs: %d\n', numel(run_candidates));
    if isempty(run_candidates)
        error('No .mat files found after skip_runs.');
    end

    % One load per candidate: calibration-only runs skipped inside process_single_run.
    run_tbls = {};
    run_trials_tbls = {};
    run_files = {};
    skipped_calibration_runs = {};
    fprintf('\n=== Reading runs ===\n');
    for k = 1:numel(run_candidates)
        fpath = run_candidates{k};
        [~, base, ext] = fileparts(fpath);
        t0 = datetime('now');
        fprintf('Reading %s%s at %s ...\n', base, ext, char(t0, 'yyyy-MM-dd HH:mm:ss'));
        [trials_k, summary_k, is_cal] = process_single_run( ...
            fpath, numel(run_files) + 1, sprintf('Run%d', numel(run_files) + 1), STATE);
        t1 = datetime('now');
        if is_cal
            skipped_calibration_runs{end+1, 1} = fpath; %#ok<AGROW>
            fprintf('  -> eye-cal only (effector==0) — skipped  [%.1f s]\n', ...
                seconds(t1 - t0));
            continue;
        end
        run_files{end+1, 1} = fpath; %#ok<AGROW>
        run_trials_tbls{end+1, 1} = trials_k; %#ok<AGROW>
        run_tbls{end+1, 1} = summary_k; %#ok<AGROW>
        fprintf('  -> REACH run kept as Run%d  (%d trials)  [%.1f s]\n', ...
            numel(run_files), height(trials_k), seconds(t1 - t0));
        [~, run_base, ~] = fileparts(fpath);
        report_invalid_timing_trials( ...
            trials_k, sprintf('Run%d', numel(run_files)), out_dir, run_base);
    end
    fprintf('\nSelected reach-relevant runs: %d of %d found\n', ...
        numel(run_files), numel(all_run_files));
    for i = 1:numel(run_files)
        fprintf('  Run%d: %s\n', i, run_files{i});
    end
    if ~isempty(skipped_calibration_runs)
        fprintf('Skipped eye-cal runs: %d\n', numel(skipped_calibration_runs));
        for i = 1:numel(skipped_calibration_runs)
            fprintf('  - %s\n', skipped_calibration_runs{i});
        end
    end
    if isempty(run_files)
        error('No hand-reach .mat files found after filtering/skipping.');
    end

    session_date = infer_session_date(input_path, run_files);
    date_str = char(session_date, 'yyyy-MM-dd');

    n_runs = numel(run_files);
    excel_fullpath = fullfile(out_dir, sprintf('%s_%s.xlsx', animal_name, date_str));

    day_tbl = vertcat(run_tbls{:});
    if ~isempty(day_tbl)
        day_tbl.Condition(:) = "Day";
    else
        day_tbl = empty_run_summary_table("Day", 0, "");
    end

    day_trials_tbl = vertcat(run_trials_tbls{:});
    if isempty(day_trials_tbl)
        day_trials_tbl = empty_trial_table();
    end
    if ~isempty(day_trials_tbl)
        day_trials_tbl.Condition(:) = "Day";
    end

    plot_files = cell(n_runs + 1, 1);
    for k = 1:n_runs
        [~, run_base, ~] = fileparts(run_files{k});
        plot_files{k} = make_run_figure(run_trials_tbls{k}, out_dir, run_base);
    end
    session_title = sprintf('%s %s (%d runs)', animal_name, date_str, n_runs);
    plot_files{end} = make_session_figure( ...
        day_trials_tbl, run_trials_tbls, out_dir, ...
        sprintf('%s_%s_session', animal_name, date_str), session_title);

    if write_excel
        write_tables_to_excel(excel_fullpath, run_tbls, run_trials_tbls, ...
            day_tbl, day_trials_tbl);
    else
        excel_fullpath = "";
    end

    out = struct();
    out.animal_name = animal_name;
    out.session_date = session_date;
    out.session_folder = session_folder;
    out.output_base = char(output_base);
    out.run_files = run_files;
    out.n_runs = n_runs;
    out.skipped_calibration_runs = skipped_calibration_runs;
    out.skipped_user_runs = skipped_user_runs;
    out.write_excel = write_excel;
    out.excel_fullpath = excel_fullpath;
    out.out_dir = out_dir;
    out.plot_files = plot_files;
    out.run_tables = run_tbls;
    out.day_table = day_tbl;
    out.run_trials_tables = run_trials_tbls;
    out.day_trials_table = day_trials_tbl;

    fprintf('\nAnalysis complete successfully, data saved in %s\n', out_dir);
end

%% =============================================================================
% SINGLE-RUN PROCESSING
%% =============================================================================

function [trials_tbl, summary_tbl, is_cal] = process_single_run(filepath, run_index, condition_label, STATE)
% One .mat load -> trial table + one-row run summary. is_cal=true if all eye-cal (effector==0).

    is_cal = false;
    data = load(filepath);
    if ~isfield(data, 'trial')
        error('File does not contain variable "trial": %s', filepath);
    end

    if isempty(data.trial)
        trials_tbl = empty_trial_table();
        summary_tbl = empty_run_summary_table(condition_label, run_index, filepath);
        return;
    end

    if all_eye_calibration_trials(data.trial)
        is_cal = true;
        trials_tbl = empty_trial_table();
        summary_tbl = empty_run_summary_table(condition_label, run_index, filepath);
        return;
    end

    trials = filter_reach_trials(data.trial);
    reach_paradigm = get_reach_paradigm_type(data, trials);
    n_trials = numel(trials);
    [del_hold, del_hold_var, cue_hold, cue_hold_var] = get_delay_timing_params(data, trials);

    if n_trials == 0
        trials_tbl = empty_trial_table();
        summary_tbl = empty_run_summary_table(condition_label, run_index, filepath);
        summary_tbl.ReachParadigm(:) = reach_paradigm;
        summary_tbl.DelTimeHold(:) = del_hold;
        summary_tbl.DelTimeHoldVar(:) = del_hold_var;
        return;
    end

    condition_col = repmat(string(condition_label), n_trials, 1);
    run_col = repmat(int32(run_index), n_trials, 1);
    trial_col = int32((1:n_trials)');
    file_col = repmat(string(filepath), n_trials, 1);
    task_type_col = repmat("", n_trials, 1);
    delay_col = NaN(n_trials, 1);
    target_acq_time_col = NaN(n_trials, 1);
    rt_fix_sensor_col = NaN(n_trials, 1);
    mt_sensor_fix_col = NaN(n_trials, 1);
    rt_go_move_col = NaN(n_trials, 1);
    mt_move_target_col = NaN(n_trials, 1);
    target_col = repmat("", n_trials, 1);
    hand_col = repmat("", n_trials, 1);
    success_col = zeros(n_trials, 1);
    abort_reason_col = repmat("", n_trials, 1);
    time_until_abort_col = NaN(n_trials, 1);
    delay_for_hist_col = NaN(n_trials, 1);
    abort_after_cue_col = zeros(n_trials, 1);
    fix_hand_known_col = zeros(n_trials, 1);
    cue_space_assignable_col = zeros(n_trials, 1);

    S = init_run_summary_counters(n_trials);

    for i = 1:n_trials
        trial = trials(i);

        choice = get_scalar_num_field(trial, 'choice');
        if choice == 1
            task_type_col(i) = "Free";
        elseif choice == 0
            task_type_col(i) = "Instructed";
        end

        delay_col(i) = get_delay_period_duration(trial, STATE);
        target_acq_time_col(i) = get_target_acq_time(trial, STATE);

        success_col(i) = get_scalar_num_field(trial, 'success');
        if isnan(success_col(i))
            success_col(i) = 0;
        end
        if success_col(i) == 1
            S.successful_trials = S.successful_trials + 1;
            [rt_fix_sensor_col(i), mt_sensor_fix_col(i), rt_go_move_col(i), mt_move_target_col(i)] = ...
                get_trial_timing_metrics(trial, STATE);
        else
            S.failed_trials = S.failed_trials + 1;
        end

        target_pos = get_target_pos(trial);
        if target_pos == 1
            target_col(i) = "Left";
        elseif target_pos == 2
            target_col(i) = "Right";
        end

        rh = get_scalar_num_field(trial, 'reach_hand');
        if rh == 1
            hand_col(i) = "Left";
            S.left_hand_all = S.left_hand_all + 1;
        elseif rh == 2
            hand_col(i) = "Right";
            S.right_hand_all = S.right_hand_all + 1;
        end

        fix_hand_known_col(i) = double(trial_reached_fixation(trial, STATE) && ismember(rh, [1, 2]));
        cue_space_assignable_col(i) = double( ...
            trial_cue_or_target_shown(trial, STATE) && ismember(choice, [0, 1]) && ...
            ismember(rh, [1, 2]) && ismember(target_pos, [1, 2]));

        if success_col(i) == 0
            reason = get_abort_reason(trial);
            if strlength(string(reason)) > 0
                abort_reason_col(i) = string(lower(reason));
            end
            [abort_after_cue_col(i), delay_for_hist_col(i), time_until_abort_col(i)] = ...
                compute_delay_hist_fields(trial, success_col(i), STATE, delay_col(i), reason);
            S = bump_abort_reason_counter(S, reason);
        else
            abort_reason_col(i) = "";
            abort_after_cue_col(i) = 0;
            % Same helper as aborts: cue-aligned wait (NOT DelayDuration / DEL_PER alone).
            [~, delay_for_hist_col(i), time_until_abort_col(i)] = ...
                compute_delay_hist_fields(trial, 1, STATE, delay_col(i), "");
        end

        if fix_hand_known_col(i) == 1
            S = bump_hand_choice_totals(S, choice, rh, success_col(i));
        end

        if success_col(i) == 1
            if target_pos == 1
                S.left_targets_all = S.left_targets_all + 1;
            elseif target_pos == 2
                S.right_targets_all = S.right_targets_all + 1;
            end
            S = bump_hand_target_combo(S, choice, rh, target_pos);
        end
    end

    trials_tbl = table( ...
        condition_col, run_col, trial_col, file_col, task_type_col, ...
        delay_col, target_acq_time_col, rt_fix_sensor_col, mt_sensor_fix_col, ...
        rt_go_move_col, mt_move_target_col, target_col, hand_col, success_col, ...
        abort_reason_col, time_until_abort_col, delay_for_hist_col, abort_after_cue_col, ...
        fix_hand_known_col, cue_space_assignable_col, ...
        repmat(del_hold, n_trials, 1), repmat(del_hold_var, n_trials, 1), ...
        repmat(cue_hold, n_trials, 1), repmat(cue_hold_var, n_trials, 1), ...
        'VariableNames', { ...
            'Condition', 'Run', 'Trial', 'File', 'TaskType', 'DelayDuration', 'TargetAcqTime', ...
            'RTFixToSensorRelease', 'MTSensorToFixHold', 'RTGoToMovement', 'MTMovementToTarget', ...
            'Target', 'Hand', 'Success', 'reason_of_abort', 'TimeUntilAbort', ...
            'DelayForHist', 'AbortAfterCue', 'FixHandKnown', 'CueSpaceAssignable', ...
            'DelTimeHold', 'DelTimeHoldVar', 'CueTimeHold', 'CueTimeHoldVar'});

    summary_tbl = pack_run_summary_table( ...
        condition_label, run_index, filepath, reach_paradigm, S, del_hold, del_hold_var);
end

function S = init_run_summary_counters(n_trials)
% Zeroed counters for pack_run_summary_table.
    S = struct();
    S.all_trials = n_trials;
    S.successful_trials = 0;
    S.failed_trials = 0;
    S.left_hand_all = 0;
    S.right_hand_all = 0;
    S.left_targets_all = 0;
    S.right_targets_all = 0;
    S.instructed_LL = 0; S.instructed_LR = 0; S.instructed_RL = 0; S.instructed_RR = 0;
    S.free_LL = 0; S.free_LR = 0; S.free_RL = 0; S.free_RR = 0;
    S.abort_use_incorrect_hand = 0;
    S.abort_hnd_fix_acq_state = 0;
    S.abort_hnd_del_per_state = 0;
    S.abort_hnd_tar_acq_state = 0;
    S.abort_hnd_fix_hold_state = 0;
    S.free_left_total = 0; S.free_left_success = 0;
    S.free_right_total = 0; S.free_right_success = 0;
    S.instructed_left_total = 0; S.instructed_left_success = 0;
    S.instructed_right_total = 0; S.instructed_right_success = 0;
end

function S = bump_abort_reason_counter(S, reason)
% Increment the first matching abort-code bucket (substring match on abort_code).
    reason_lower = lower(string(reason));
    if contains(reason_lower, 'abort_use_incorrect_hand')
        S.abort_use_incorrect_hand = S.abort_use_incorrect_hand + 1;
    elseif contains(reason_lower, 'abort_hnd_fix_acq_state')
        S.abort_hnd_fix_acq_state = S.abort_hnd_fix_acq_state + 1;
    elseif contains(reason_lower, 'abort_hnd_del_per_state')
        S.abort_hnd_del_per_state = S.abort_hnd_del_per_state + 1;
    elseif contains(reason_lower, 'abort_hnd_tar_acq_state')
        S.abort_hnd_tar_acq_state = S.abort_hnd_tar_acq_state + 1;
    elseif contains(reason_lower, 'abort_hnd_fix_hold_state')
        S.abort_hnd_fix_hold_state = S.abort_hnd_fix_hold_state + 1;
    end
end

function S = bump_hand_choice_totals(S, choice, rh, success)
% Tallies used for Free/Instr Left/Right success-rate columns. choice must be 0 or 1.
    if isnan(rh) || ~ismember(choice, [0, 1])
        return;
    end
    if choice == 1
        if rh == 1
            S.free_left_total = S.free_left_total + 1;
            S.free_left_success = S.free_left_success + success;
        elseif rh == 2
            S.free_right_total = S.free_right_total + 1;
            S.free_right_success = S.free_right_success + success;
        end
    else
        if rh == 1
            S.instructed_left_total = S.instructed_left_total + 1;
            S.instructed_left_success = S.instructed_left_success + success;
        elseif rh == 2
            S.instructed_right_total = S.instructed_right_total + 1;
            S.instructed_right_success = S.instructed_right_success + success;
        end
    end
end

function S = bump_hand_target_combo(S, choice, rh, target_pos)
% Successful trials only: increment Instr_*/Free_* LL/LR/RL/RR cells.
    if isnan(rh) || isnan(target_pos) || ~ismember(choice, [0, 1])
        return;
    end
    if choice == 0
        if rh == 1 && target_pos == 1
            S.instructed_LL = S.instructed_LL + 1;
        elseif rh == 1 && target_pos == 2
            S.instructed_LR = S.instructed_LR + 1;
        elseif rh == 2 && target_pos == 1
            S.instructed_RL = S.instructed_RL + 1;
        elseif rh == 2 && target_pos == 2
            S.instructed_RR = S.instructed_RR + 1;
        end
    else
        if rh == 1 && target_pos == 1
            S.free_LL = S.free_LL + 1;
        elseif rh == 1 && target_pos == 2
            S.free_LR = S.free_LR + 1;
        elseif rh == 2 && target_pos == 1
            S.free_RL = S.free_RL + 1;
        elseif rh == 2 && target_pos == 2
            S.free_RR = S.free_RR + 1;
        end
    end
end

function summary_tbl = pack_run_summary_table(condition_label, run_index, filepath, reach_paradigm, S, del_hold, del_hold_var)
    if nargin < 6, del_hold = NaN; end
    if nargin < 7, del_hold_var = NaN; end
    initiated_trials = S.successful_trials + S.failed_trials;
    summary_tbl = table( ...
        string(condition_label), run_index, string(filepath), reach_paradigm, ...
        S.all_trials, initiated_trials, S.successful_trials, S.failed_trials, ...
        safe_pct(initiated_trials, S.all_trials), ...
        safe_pct(S.successful_trials, S.all_trials), ...
        safe_pct(S.successful_trials, initiated_trials), ...
        S.left_hand_all, S.right_hand_all, S.left_targets_all, S.right_targets_all, ...
        S.instructed_LL, S.instructed_LR, S.instructed_RL, S.instructed_RR, ...
        S.free_LL, S.free_LR, S.free_RL, S.free_RR, ...
        S.free_left_total, S.free_left_success, safe_pct(S.free_left_success, S.free_left_total), ...
        S.free_right_total, S.free_right_success, safe_pct(S.free_right_success, S.free_right_total), ...
        S.instructed_left_total, S.instructed_left_success, safe_pct(S.instructed_left_success, S.instructed_left_total), ...
        S.instructed_right_total, S.instructed_right_success, safe_pct(S.instructed_right_success, S.instructed_right_total), ...
        S.abort_use_incorrect_hand, S.abort_hnd_fix_acq_state, S.abort_hnd_del_per_state, ...
        S.abort_hnd_tar_acq_state, S.abort_hnd_fix_hold_state, ...
        del_hold, del_hold_var, ...
        'VariableNames', { ...
            'Condition', 'Run', 'File', 'ReachParadigm', 'AllTrials', 'InitiatedTrials', ...
            'SuccessfulTrials', 'FailedTrials', 'PctInitiatedOfAll', 'PctSuccessfulOfAll', ...
            'PctSuccessfulOfInitiated', 'LeftHandAll', 'RightHandAll', 'LeftTargets', 'RightTargets', ...
            'Instr_LL', 'Instr_LR', 'Instr_RL', 'Instr_RR', ...
            'Free_LL', 'Free_LR', 'Free_RL', 'Free_RR', ...
            'FreeLeftTotal', 'FreeLeftSuccess', 'FreeLeftSuccessPct', ...
            'FreeRightTotal', 'FreeRightSuccess', 'FreeRightSuccessPct', ...
            'InstrLeftTotal', 'InstrLeftSuccess', 'InstrLeftSuccessPct', ...
            'InstrRightTotal', 'InstrRightSuccess', 'InstrRightSuccessPct', ...
            'abort_use_incorrect_hand', 'abort_hnd_fix_acq_state', 'abort_hnd_del_per_state', ...
            'abort_hnd_tar_acq_state', 'abort_hnd_fix_hold_state', ...
            'DelTimeHold', 'DelTimeHoldVar'});
end

%% =============================================================================
% TRIAL STATE / DELAY HELPERS (used inside process_single_run; not a separate pipeline stage)
%% =============================================================================

% Duration of DEL_PER state from states/states_onset (NaN if absent).
function delay_dur = get_delay_period_duration(trial, STATE)
    delay_dur = NaN;
    if ~isfield(trial, 'states') || ~isfield(trial, 'states_onset')
        return;
    end
    states = trial.states(:);
    onsets = trial.states_onset(:);
    delay_idx = find(states == STATE.DEL_PER, 1, 'first');
    if ~isempty(delay_idx) && delay_idx < numel(onsets)
        delay_dur = onsets(delay_idx + 1) - onsets(delay_idx);
    end
end

% Time from end of delay period to first TAR_HOL onset after delay (NaN if not reached).
function target_acq_time = get_target_acq_time(trial, STATE)
    target_acq_time = NaN;
    if ~isfield(trial, 'states') || ~isfield(trial, 'states_onset')
        return;
    end
    states = trial.states(:);
    onsets = trial.states_onset(:);
    delay_idx = find(states == STATE.DEL_PER, 1, 'first');
    if isempty(delay_idx) || delay_idx + 1 > numel(onsets)
        return;
    end
    end_delay = onsets(delay_idx + 1);
    idx_hold = find(states == STATE.TAR_HOL);
    idx_hold = idx_hold(idx_hold > delay_idx);
    if ~isempty(idx_hold) && idx_hold(1) <= numel(onsets)
        target_acq_time = onsets(idx_hold(1)) - end_delay;
    end
end

% Map trial outcome to DelayForHist / AbortAfterCue for the delay histogram.
% BOTH success and abort-after-cue use the SAME time origin: CUE_ON onset.
%
% Success:
%   (end of DEL_PER) - t_CUE_ON  = completed cue hold + delay hold
%
% Abort (cue/delay epoch) — use fixation/hand BREAK time, NOT ABORT state stamp:
%   aborted_state == CUE_ON:
%       DelayForHist = aborted_state_duration
%       (time in CUE_ON until violation; trial never reaches DEL_PER)
%   aborted_state == DEL_PER:
%       DelayForHist = (t_DEL_PER - t_CUE_ON) + aborted_state_duration
%       (completed cue + time in DEL_PER until violation)
% ABORT onset is typically ~0.25 s later than the break — do not use it for the hist.
function [abort_after_cue, delay_for_hist, time_until_abort] = compute_delay_hist_fields( ...
        trial, success, STATE, delay_duration, reason)
    abort_after_cue = 0;
    delay_for_hist = NaN;
    time_until_abort = NaN;

    t_cue = get_state_event_onset(trial, STATE.CUE_ON);

    if success == 1
        t_del_end = get_delay_period_end_time(trial, STATE);
        if ~isnan(t_cue) && ~isnan(t_del_end)
            delay_for_hist = t_del_end - t_cue;
        elseif ~isnan(delay_duration)
            % Fallback only if CUE_ON missing: DEL_PER duration alone (NOT preferred).
            delay_for_hist = delay_duration;
        end
        return;
    end

    reason_lower = lower(string(reason));
    aborted_state = get_trial_aborted_state(trial, STATE);
    is_cue_abort = ismember(aborted_state, [STATE.CUE_ON, STATE.DEL_PER]) || ...
        contains(reason_lower, 'del_per') || ...
        contains(reason_lower, 'abort_hnd_del_per_state') || ...
        contains(reason_lower, 'cue_on') || ...
        contains(reason_lower, 'cue abort');

    if ~is_cue_abort
        return;
    end

    abort_after_cue = 1;
    abr_dur = get_aborted_state_duration(trial);
    t_del = get_state_event_onset(trial, STATE.DEL_PER);

    if ~isnan(abr_dur) && abr_dur >= 0
        if aborted_state == STATE.CUE_ON || (isnan(aborted_state) && contains(reason_lower, 'cue_on'))
            delay_for_hist = abr_dur;
            time_until_abort = delay_for_hist;
            return;
        end
        if aborted_state == STATE.DEL_PER || contains(reason_lower, 'del_per')
            if ~isnan(t_cue) && ~isnan(t_del)
                delay_for_hist = (t_del - t_cue) + abr_dur;
            else
                % No cue stamp: report time-in-delay only (explicitly different origin).
                delay_for_hist = abr_dur;
            end
            time_until_abort = delay_for_hist;
            return;
        end
    end

    % Fallback (no aborted_state_duration): ABORT stamp — overestimates break time.
    t_end = get_trial_end_time(trial);
    if ~isnan(t_cue) && ~isnan(t_end)
        delay_for_hist = t_end - t_cue;
        time_until_abort = delay_for_hist;
        return;
    end
    if ~isnan(t_del) && ~isnan(t_end)
        delay_for_hist = t_end - t_del;
        time_until_abort = delay_for_hist;
    end
end

function abr_dur = get_aborted_state_duration(trial)
% Seconds spent in aborted_state until the behavioral violation (not ABORT stamp).
    abr_dur = NaN;
    if isfield(trial, 'aborted_state_duration') && ~isempty(trial.aborted_state_duration)
        abr_dur = double(trial.aborted_state_duration(1));
    end
end

function t_del_end = get_delay_period_end_time(trial, STATE)
% Onset of the state that ends DEL_PER (usually TAR_ACQ), else NaN.
    t_del_end = NaN;
    if ~isfield(trial, 'states') || ~isfield(trial, 'states_onset')
        return;
    end
    states = trial.states(:);
    onsets = trial.states_onset(:);
    delay_idx = find(states == STATE.DEL_PER, 1, 'first');
    if ~isempty(delay_idx) && delay_idx < numel(onsets)
        t_del_end = onsets(delay_idx + 1);
    end
end

% Last state before ABORT marker, or trial.aborted_state when present.
function aborted_state = get_trial_aborted_state(trial, STATE)
    aborted_state = NaN;
    if isfield(trial, 'aborted_state')
        aborted_state = get_scalar_num_field(trial, 'aborted_state');
        if ~isnan(aborted_state)
            return;
        end
    end
    if ~isfield(trial, 'states') || isempty(trial.states)
        return;
    end
    states = trial.states(:);
    abort_idx = find(states == STATE.ABORT, 1, 'last');
    if ~isempty(abort_idx) && abort_idx > 1
        aborted_state = states(abort_idx - 1);
    elseif ~isempty(states)
        aborted_state = states(end);
    end
end

% Last non-NaN states_onset timestamp — proxy for trial end when aborting.
function t_end = get_trial_end_time(trial)
    t_end = NaN;
    if isfield(trial, 'states_onset') && ~isempty(trial.states_onset)
        onsets = trial.states_onset(:);
        onsets = onsets(~isnan(onsets));
        if ~isempty(onsets)
            t_end = onsets(end);
        end
    end
end

%% =============================================================================
% VISUALIZATION — tiledlayout(3,4) run + session
%% =============================================================================

function plot_path = make_run_figure(trials_tbl, out_dir, run_base)
    fig = figure('Visible', 'off', 'Position', [40 40 2000 1100]);
    tl = tiledlayout(fig, 3, 4, 'TileSpacing', 'compact', 'Padding', 'compact');
    fill_session_or_run_tiles(tl, trials_tbl, {}, false);
    sgtitle(tl, sprintf('Run: %s', run_base), 'FontWeight', 'bold', 'Interpreter', 'none');
    set_sgtitle_interpreter_none(fig);
    plot_path = fullfile(out_dir, [run_base '.pdf']);
    save_figure_pdf(fig, plot_path);
    close(fig);
end

function plot_path = make_session_figure(day_trials_tbl, run_trials_tbls, out_dir, base_name, title_str)
    fig = figure('Visible', 'off', 'Position', [40 40 2000 1100]);
    tl = tiledlayout(fig, 3, 4, 'TileSpacing', 'compact', 'Padding', 'compact');
    fill_session_or_run_tiles(tl, day_trials_tbl, run_trials_tbls, true);
    sgtitle(tl, title_str, 'FontWeight', 'bold', 'Interpreter', 'none');
    set_sgtitle_interpreter_none(fig);
    plot_path = fullfile(out_dir, [base_name '.pdf']);
    save_figure_pdf(fig, plot_path);
    close(fig);
end

function fill_session_or_run_tiles(tl, trials_tbl, run_trials_tbls, is_session)
    nexttile(tl, 1);
    plot_success_lh_rh(trials_tbl, run_trials_tbls, is_session);

    nexttile(tl, 2);
    plot_success_instr_space(trials_tbl, run_trials_tbls, is_session);

    nexttile(tl, 3);
    plot_free_choice_percent(trials_tbl, run_trials_tbls, is_session);

    nexttile(tl, 4);
    plot_uncrossed_crossed(trials_tbl, run_trials_tbls, is_session);

    % Fixation epoch: only hand known — combine instr/choice and space
    nexttile(tl, 5);
    plot_timing_by_hand(trials_tbl, run_trials_tbls, is_session, ...
        'RTFixToSensorRelease', 'RT sensor release (s)');

    nexttile(tl, 6);
    plot_timing_by_hand(trials_tbl, run_trials_tbls, is_session, ...
        'MTSensorToFixHold', 'MT to fixation (s)');

    nexttile(tl, 7);
    plot_timing_eight_bars(trials_tbl, run_trials_tbls, is_session, ...
        'RTGoToMovement', 'RT to target (s)');

    nexttile(tl, 8);
    plot_timing_eight_bars(trials_tbl, run_trials_tbls, is_session, ...
        'MTMovementToTarget', 'MT to target (s)');

    nexttile(tl, 9);
    plot_rt_vs_successful_trial(trials_tbl, is_session);

    nexttile(tl, 10);
    plot_delay_percent_histogram(trials_tbl);

    nexttile(tl, 11); axis off;
    nexttile(tl, 12); axis off;
end

function c = plot_colors()
% Exactly 4 colors: blue/green = hand, dark/bright = instr/choice.
    c = struct();
    c.lh_instr = [0.10, 0.35, 0.75];   % dark blue
    c.lh_choice = [0.45, 0.75, 1.00];  % bright blue
    c.rh_instr = [0.05, 0.45, 0.20];   % dark green
    c.rh_choice = [0.35, 0.85, 0.45];  % bright green
    c.lh = c.lh_choice;  % hand-only panels use bright
    c.rh = c.rh_choice;
end

function color = color_hand_task(hand, task)
% hand: "Left"|"Right"; task: "Instructed"|"Free"|"" (empty -> bright hand color)
    c = plot_colors();
    is_left = (hand == "Left") || strcmp(hand, 'Left');
    if nargin < 2 || strlength(string(task)) == 0
        if is_left, color = c.lh; else, color = c.rh; end
        return;
    end
    is_instr = (task == "Instructed") || strcmp(task, 'Instructed');
    if is_left
        if is_instr, color = c.lh_instr; else, color = c.lh_choice; end
    else
        if is_instr, color = c.rh_instr; else, color = c.rh_choice; end
    end
end

function [labels, colors] = get_eight_bar_config()
% Order: LH L I, LH L C, LH R I, LH R C, RH L I, RH L C, RH R I, RH R C
% Colors: only hand x instr/choice (space shares color).
% Used for RT/MT panels (choice cells OK for timing conditioned on chosen outcome).
    labels = {'LH L I','LH L C','LH R I','LH R C','RH L I','RH L C','RH R I','RH R C'};
    hands = ["Left","Left","Left","Left","Right","Right","Right","Right"];
    tasks = ["Instructed","Free","Instructed","Free","Instructed","Free","Instructed","Free"];
    colors = zeros(8, 3);
    for i = 1:8
        colors(i, :) = color_hand_task(hands(i), tasks(i));
    end
end

function [labels, colors] = get_instr_space_bar_config()
% Instructed-only hand×space (no Free/C). Free "success by chosen space" is preference-biased.
    labels = {'LH L', 'LH R', 'RH L', 'RH R'};
    hands = ["Left", "Left", "Right", "Right"];
    colors = zeros(4, 3);
    for i = 1:4
        colors(i, :) = color_hand_task(hands(i), "Instructed");
    end
end

function [combo_labels, combo_keys] = get_space_combo_labels()
    combo_labels = {'LH L', 'LH R', 'RH L', 'RH R'};
    combo_keys = {'Left|Left', 'Left|Right', 'Right|Left', 'Right|Right'};
end

function label_bar_n(x, ns, y_ref)
% Print trial count at bottom of each bar (number only, no 'n=').
    if nargin < 3
        y_ref = 0;
    end
    yl = ylim;
    y_txt = y_ref + 0.02 * max(yl(2) - yl(1), eps);
    ns = ns(:)';
    for i = 1:min(numel(x), numel(ns))
        text(x(i), y_txt, sprintf('%d', ns(i)), ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
            'FontSize', 8, 'FontWeight', 'bold', 'Color', [0.1 0.1 0.1], ...
            'Clipping', 'off');
    end
end

function overlay_trial_dots(x, trial_cells, colors)
% Individual trial points: matching bar face color + thin white outline.
    for g = 1:min(numel(x), numel(trial_cells))
        vals = trial_cells{g}(:);
        vals = vals(~isnan(vals));
        if isempty(vals)
            continue;
        end
        n = numel(vals);
        if n == 1
            xx = x(g);
        else
            xx = x(g) + linspace(-0.16, 0.16, n);
        end
        col = colors(min(g, size(colors, 1)), :);
        scatter(xx, vals, 24, 'o', ...
            'MarkerFaceColor', col, ...
            'MarkerEdgeColor', 'w', ...
            'LineWidth', 0.75, ...
            'MarkerFaceAlpha', 1, ...
            'HandleVisibility', 'off');
    end
end

function overlay_run_means(x, run_trials_tbls, stats_fn, colors)
% Session: per-run means, matching bar color, white edge.
    if isempty(run_trials_tbls)
        return;
    end
    for k = 1:numel(run_trials_tbls)
        vals = stats_fn(run_trials_tbls{k});
        if size(vals, 1) > 1
            vals = vals(1, :);
        end
        vals = vals(:)';
        for i = 1:min(numel(x), numel(vals))
            if isnan(vals(i))
                continue;
            end
            scatter(x(i), vals(i), 36, 'o', ...
                'MarkerFaceColor', colors(min(i, size(colors, 1)), :), ...
                'MarkerEdgeColor', 'w', 'LineWidth', 1.1, ...
                'HandleVisibility', 'off');
        end
    end
end

function plot_success_lh_rh(trials_tbl, run_trials_tbls, is_session)
    [pct, n_all, n_succ] = success_lh_rh_stats(trials_tbl);
    c = plot_colors();
    colors = [c.lh; c.rh];
    x = 1:2;
    bh = bar(x, pct, 0.65, 'FaceColor', 'flat', 'EdgeColor', 'k');
    bh.CData = colors;
    hold on;
    if is_session
        overlay_run_means(x, run_trials_tbls, @(t) success_lh_rh_pct_only(t), colors);
    end
    set(gca, 'XTick', x, 'XTickLabel', {'LH', 'RH'}, 'FontWeight', 'bold', ...
        'TickLabelInterpreter', 'none');
    ylabel('Success rate (%)', 'FontWeight', 'bold');
    title(sprintf(['Success by hand (fixation shown, hand known)\n' ...
        '%d trials (%d LH, %d RH), %d successful.'], ...
        sum(n_all), n_all(1), n_all(2), sum(n_succ)), ...
        'FontWeight', 'bold', 'Interpreter', 'none');
    ylim([0 100]);
    grid on;
    label_bar_n(x, n_succ, 0);
end

function pct = success_lh_rh_pct_only(tbl)
    [pct, ~, ~] = success_lh_rh_stats(tbl);
end

function [pct, n_all, n_succ] = success_lh_rh_stats(tbl)
    pct = [NaN NaN];
    n_all = [0 0];
    n_succ = [0 0];
    if isempty(tbl) || height(tbl) == 0
        return;
    end
    hands = ["Left", "Right"];
    for i = 1:2
        idx = tbl.FixHandKnown == 1 & tbl.Hand == hands(i);
        n_all(i) = sum(idx);
        n_succ(i) = sum(idx & tbl.Success == 1);
        if n_all(i) > 0
            pct(i) = n_succ(i) / n_all(i) * 100;
        end
    end
end

function plot_success_instr_space(trials_tbl, run_trials_tbls, is_session)
% Instructed success only (hand×space). Free omitted: chosen space is preference, not a condition.
    [labels, colors] = get_instr_space_bar_config();
    [pct, n_all, n_succ] = success_instr_space_stats(trials_tbl);
    x = 1:4;
    bh = bar(x, pct, 0.7, 'FaceColor', 'flat', 'EdgeColor', 'k');
    bh.CData = colors;
    hold on;
    if is_session
        overlay_run_means(x, run_trials_tbls, @success_instr_space_pct_only, colors);
    end
    set(gca, 'XTick', x, 'XTickLabel', labels, 'FontWeight', 'bold', ...
        'TickLabelInterpreter', 'none');
    xtickangle(20);
    ylabel('Success rate (%)', 'FontWeight', 'bold');
    title(sprintf(['Instructed success (cue/target shown, hand+space known)\n' ...
        '%d instructed trials, %d successful.  (Free omitted — preference-biased)'], ...
        sum(n_all), sum(n_succ)), ...
        'FontWeight', 'bold', 'Interpreter', 'none');
    ylim([0 100]);
    grid on;
    label_bar_n(x, n_succ, 0);
end

function pct = success_instr_space_pct_only(tbl)
    [pct, ~, ~] = success_instr_space_stats(tbl);
end

function [pct, n_all, n_succ] = success_instr_space_stats(tbl)
    pct = nan(1, 4);
    n_all = zeros(1, 4);
    n_succ = zeros(1, 4);
    if isempty(tbl) || height(tbl) == 0
        return;
    end
    combos = {'Left','Left'; 'Left','Right'; 'Right','Left'; 'Right','Right'};
    for k = 1:4
        idx = tbl.CueSpaceAssignable == 1 & tbl.TaskType == "Instructed" & ...
            tbl.Hand == combos{k,1} & tbl.Target == combos{k,2};
        n_all(k) = sum(idx);
        n_succ(k) = sum(idx & tbl.Success == 1);
        if n_all(k) > 0
            pct(k) = n_succ(k) / n_all(k) * 100;
        end
    end
end

function plot_free_choice_percent(trials_tbl, run_trials_tbls, is_session)
    [labels, ~] = get_space_combo_labels();
    c = plot_colors();
    colors = [c.lh_choice; c.lh_choice; c.rh_choice; c.rh_choice];
    [pct, ns] = free_choice_pct_stats(trials_tbl);
    x = 1:4;
    bh = bar(x, pct, 0.65, 'FaceColor', 'flat', 'EdgeColor', 'k');
    bh.CData = colors;
    hold on;
    if is_session
        overlay_run_means(x, run_trials_tbls, @free_choice_pct_only, colors);
    end
    set(gca, 'XTick', x, 'XTickLabel', labels, 'FontWeight', 'bold', ...
        'TickLabelInterpreter', 'none');
    xtickangle(20);
    ylabel('% of successful choice', 'FontWeight', 'bold');
    title(sprintf(['Free choice (share of successful choice trials)\n' ...
        '%d successful (%d LH L, %d LH R, %d RH L, %d RH R).'], ...
        sum(ns), ns(1), ns(2), ns(3), ns(4)), ...
        'FontWeight', 'bold', 'Interpreter', 'none');
    ylim([0 100]);
    grid on;
    label_bar_n(x, ns, 0);
end

function pct = free_choice_pct_only(tbl)
    [pct, ~] = free_choice_pct_stats(tbl);
end

function [pct, ns] = free_choice_pct_stats(tbl)
    pct = nan(1, 4);
    ns = zeros(1, 4);
    if isempty(tbl) || height(tbl) == 0
        return;
    end
    idx = tbl.Success == 1 & tbl.TaskType == "Free";
    n_tot = sum(idx);
    if n_tot == 0
        return;
    end
    combos = {'Left','Left'; 'Left','Right'; 'Right','Left'; 'Right','Right'};
    for c = 1:4
        ns(c) = sum(idx & tbl.Hand == combos{c,1} & tbl.Target == combos{c,2});
        pct(c) = ns(c) / n_tot * 100;
    end
end

function plot_uncrossed_crossed(trials_tbl, run_trials_tbls, is_session)
% Bars/% within each hand×task group of successful trials (unc%+cr%=100% per group).
% Session: pooled trials (vertcat). Run dots: same % per run (comparable scale).
    color_uncrossed = [0.95, 0.75, 0.10];
    color_crossed = [0.75, 0.15, 0.55];
    [pct, counts] = uncrossed_crossed_stats(trials_tbl);
    n_u = sum(counts(:, 1));
    n_c = sum(counts(:, 2));
    x = 1:4;
    x_u = x - 0.18;
    x_c = x + 0.18;
    hold on;
    bh1 = bar(x_u, pct(:, 1), 0.34, 'FaceColor', color_uncrossed, 'EdgeColor', 'k');
    bh2 = bar(x_c, pct(:, 2), 0.34, 'FaceColor', color_crossed, 'EdgeColor', 'k');
    if is_session
        for k = 1:numel(run_trials_tbls)
            [rpct, ~] = uncrossed_crossed_stats(run_trials_tbls{k});
            scatter(x_u, rpct(:, 1), 30, 'o', ...
                'MarkerFaceColor', color_uncrossed, 'MarkerEdgeColor', 'w', 'LineWidth', 1.1, ...
                'HandleVisibility', 'off');
            scatter(x_c, rpct(:, 2), 30, 'o', ...
                'MarkerFaceColor', color_crossed, 'MarkerEdgeColor', 'w', 'LineWidth', 1.1, ...
                'HandleVisibility', 'off');
        end
    end
    set(gca, 'XTick', x, 'XTickLabel', {'Free LH','Free RH','Instr LH','Instr RH'}, ...
        'FontWeight', 'bold', 'TickLabelInterpreter', 'none');
    xtickangle(20);
    ylabel('% of successful (within group)', 'FontWeight', 'bold');
    ylim([0 100]);
    title(sprintf(['Uncrossed vs crossed (successful only)\n' ...
        '%d successful (%d uncrossed, %d crossed).'], ...
        n_u + n_c, n_u, n_c), ...
        'FontWeight', 'bold', 'Interpreter', 'none');
    legend([bh1, bh2], {'Uncrossed', 'Crossed'}, 'Location', 'best');
    grid on;
    label_bar_n([x_u, x_c], [counts(:, 1)', counts(:, 2)'], 0);
end

function [pct, counts] = uncrossed_crossed_stats(tbl)
% Per row (Free/Instr × LH/RH): counts and % of successful uncrossed vs crossed.
% pct(r,:) sums to 100 when that group has any successes.
    pct = nan(4, 2);
    counts = zeros(4, 2);
    if isempty(tbl) || height(tbl) == 0
        return;
    end
    specs = { ...
        "Free", "Left"; "Free", "Right"; "Instructed", "Left"; "Instructed", "Right"};
    for r = 1:4
        base = tbl.Success == 1 & tbl.TaskType == specs{r,1} & tbl.Hand == specs{r,2};
        if specs{r,2} == "Left"
            counts(r, 1) = sum(base & tbl.Target == "Left");
            counts(r, 2) = sum(base & tbl.Target == "Right");
        else
            counts(r, 1) = sum(base & tbl.Target == "Right");
            counts(r, 2) = sum(base & tbl.Target == "Left");
        end
        n = counts(r, 1) + counts(r, 2);
        if n > 0
            pct(r, 1) = counts(r, 1) / n * 100;
            pct(r, 2) = counts(r, 2) / n * 100;
        end
    end
end

function plot_timing_by_hand(trials_tbl, run_trials_tbls, is_session, field_name, title_str)
    c = plot_colors();
    colors = [c.lh; c.rh];
    [means, sems, ns, trial_cells] = timing_by_hand_stats(trials_tbl, field_name);
    if all(isnan(means))
        text(0.5, 0.5, 'No timing data', 'HorizontalAlignment', 'center');
        axis off;
        title(title_str, 'FontWeight', 'bold', 'Interpreter', 'none');
        return;
    end
    x = 1:2;
    bh = bar(x, means, 0.65, 'FaceColor', 'flat', 'EdgeColor', 'k');
    bh.CData = colors;
    hold on;
    errorbar(x, means, sems, 'k.', 'LineWidth', 1.0, 'CapSize', 6);
    if is_session
        overlay_run_means(x, run_trials_tbls, ...
            @(t) timing_by_hand_means_only(t, field_name), colors);
    else
        overlay_trial_dots(x, trial_cells, colors);
    end
    uistack(findall(gca, 'Type', 'Scatter'), 'top');
    set(gca, 'XTick', x, 'XTickLabel', {'LH', 'RH'}, 'FontWeight', 'bold', ...
        'TickLabelInterpreter', 'none');
    ylabel('Time (s)', 'FontWeight', 'bold');
    title(sprintf('%s\n%d with valid %s (%d LH, %d RH).', ...
        title_str, sum(ns), timing_metric_kind(field_name), ns(1), ns(2)), ...
        'FontWeight', 'bold', 'Interpreter', 'none');
    grid on;
    label_bar_n(x, ns, 0);
end

function means = timing_by_hand_means_only(tbl, field_name)
    [means, ~, ~, ~] = timing_by_hand_stats(tbl, field_name);
end

function [means, sems, ns, trial_cells] = timing_by_hand_stats(tbl, field_name)
    means = [NaN NaN];
    sems = [NaN NaN];
    ns = [0 0];
    trial_cells = {[], []};
    if isempty(tbl) || height(tbl) == 0 || ~ismember(field_name, tbl.Properties.VariableNames)
        return;
    end
    hands = ["Left", "Right"];
    for i = 1:2
        idx = tbl.Success == 1 & tbl.Hand == hands(i) & ~isnan(tbl.(field_name));
        vals = tbl.(field_name)(idx);
        trial_cells{i} = vals;
        ns(i) = numel(vals);
        if ns(i) > 0
            means(i) = mean(vals);
            if ns(i) > 1
                sems(i) = std(vals) / sqrt(ns(i));
            else
                sems(i) = 0;
            end
        end
    end
end

function plot_timing_eight_bars(trials_tbl, run_trials_tbls, is_session, field_name, title_str)
    [labels, colors] = get_eight_bar_config();
    [means, sems, ns, trial_cells] = timing_eight_stats(trials_tbl, field_name);
    if all(isnan(means))
        text(0.5, 0.5, 'No timing data', 'HorizontalAlignment', 'center');
        axis off;
        title(title_str, 'FontWeight', 'bold', 'Interpreter', 'none');
        return;
    end
    x = 1:8;
    bh = bar(x, means, 0.7, 'FaceColor', 'flat', 'EdgeColor', 'k');
    bh.CData = colors;
    hold on;
    errorbar(x, means, sems, 'k.', 'LineWidth', 1.0, 'CapSize', 6);
    if is_session
        overlay_run_means(x, run_trials_tbls, ...
            @(t) timing_eight_means_only(t, field_name), colors);
    else
        overlay_trial_dots(x, trial_cells, colors);
    end
    uistack(findall(gca, 'Type', 'Scatter'), 'top');
    set(gca, 'XTick', x, 'XTickLabel', labels, 'FontWeight', 'bold', ...
        'TickLabelInterpreter', 'none');
    xtickangle(40);
    ylabel('Time (s)', 'FontWeight', 'bold');
    title(sprintf('%s\n%d with valid %s.', ...
        title_str, sum(ns), timing_metric_kind(field_name)), ...
        'FontWeight', 'bold', 'Interpreter', 'none');
    grid on;
    label_bar_n(x, ns, 0);
end

function means = timing_eight_means_only(tbl, field_name)
    [means, ~, ~, ~] = timing_eight_stats(tbl, field_name);
end

function [means, sems, ns, trial_cells] = timing_eight_stats(tbl, field_name)
    means = nan(1, 8);
    sems = nan(1, 8);
    ns = zeros(1, 8);
    trial_cells = cell(1, 8);
    if isempty(tbl) || height(tbl) == 0 || ~ismember(field_name, tbl.Properties.VariableNames)
        return;
    end
    combos = {'Left','Left'; 'Left','Right'; 'Right','Left'; 'Right','Right'};
    tasks = ["Instructed", "Free"];
    k = 0;
    for c = 1:4
        for t = 1:2
            k = k + 1;
            idx = tbl.Success == 1 & tbl.TaskType == tasks(t) & ...
                tbl.Hand == combos{c,1} & tbl.Target == combos{c,2} & ...
                ~isnan(tbl.(field_name));
            vals = tbl.(field_name)(idx);
            trial_cells{k} = vals;
            ns(k) = numel(vals);
            if ns(k) > 0
                means(k) = mean(vals);
                if ns(k) > 1
                    sems(k) = std(vals) / sqrt(ns(k));
                else
                    sems(k) = 0;
                end
            end
        end
    end
end

function plot_rt_vs_successful_trial(trials_tbl, is_session)
    if isempty(trials_tbl) || height(trials_tbl) == 0
        text(0.5, 0.5, 'No RT data', 'HorizontalAlignment', 'center');
        axis off;
        title('RT to target vs trial # (valid RT)', 'FontWeight', 'bold', 'Interpreter', 'none');
        return;
    end
    succ = trials_tbl(trials_tbl.Success == 1 & ~isnan(trials_tbl.RTGoToMovement), :);
    if isempty(succ)
        text(0.5, 0.5, 'No RT data', 'HorizontalAlignment', 'center');
        axis off;
        title('RT to target vs trial # (valid RT)', 'FontWeight', 'bold', 'Interpreter', 'none');
        return;
    end
    n_lh = sum(succ.Hand == "Left");
    n_rh = sum(succ.Hand == "Right");
    hold on;
    for hand = ["Left", "Right"]
        idx = succ.Hand == hand;
        if ~any(idx)
            continue;
        end
        y = succ.RTGoToMovement(idx);
        x = find(idx);
        col = color_hand_task(hand, "");
        plot(x, y, '-', 'Color', col, 'LineWidth', 1.0, 'HandleVisibility', 'off');
        scatter(x, y, 18, 'o', ...
            'MarkerFaceColor', col, 'MarkerEdgeColor', col, ...
            'LineWidth', 0.5, 'DisplayName', char(hand + " hand"));
    end
    if is_session && ismember('Run', succ.Properties.VariableNames)
        runs = unique(succ.Run, 'stable');
        for r = 2:numel(runs)
            boundary = find(succ.Run == runs(r), 1, 'first') - 0.5;
            xline(boundary, ':', 'Color', [0.4 0.4 0.4], 'LineWidth', 1.2, 'HandleVisibility', 'off');
        end
    end
    xlabel('Successful trial # (valid RT)', 'FontWeight', 'bold');
    ylabel('RT to target (s)', 'FontWeight', 'bold');
    title(sprintf(['RT to target vs successful trial (by hand)\n' ...
        '%d with valid RT (%d LH, %d RH).'], height(succ), n_lh, n_rh), ...
        'FontWeight', 'bold', 'Interpreter', 'none');
    legend('Location', 'best');
    grid on;
end

function plot_delay_percent_histogram(trials_tbl)
% Time from CUE_ON: success = cue+delay; abort = break time (aborted_state_duration).
    bin_width = 0.1;
    [del_hold, del_var, cue_hold, cue_var] = delay_params_from_trials(trials_tbl);
    if isnan(cue_hold), cue_hold = 0; end
    if isnan(cue_var), cue_var = 0; end
    if isnan(del_hold), del_hold = 0; end
    if isnan(del_var), del_var = 0; end

    success_vals = trials_tbl.DelayForHist(trials_tbl.Success == 1);
    abort_vals = trials_tbl.DelayForHist(trials_tbl.AbortAfterCue == 1);
    success_vals = success_vals(~isnan(success_vals));
    abort_vals = abort_vals(~isnan(abort_vals));

    if isempty(success_vals) && isempty(abort_vals)
        text(0.5, 0.5, 'No delay data', 'HorizontalAlignment', 'center');
        axis off;
        title('From cue', 'FontWeight', 'bold', 'Interpreter', 'none');
        return;
    end

    % Bins: 0:0.1:theoretical_max from task params (cue_hold+var + del_hold+var).
    % Observed values past the last edge fold into the last bin.
    theoretical_max = cue_hold + cue_var + del_hold + del_var;
    if ~(theoretical_max > 0)
        theoretical_max = 1.5;
    end
    max_edge = ceil(theoretical_max / bin_width - 1e-12) * bin_width;
    edges = 0:bin_width:max_edge;
    centers = edges(1:end-1) + bin_width / 2;
    n_succ = numel(success_vals);
    n_abort = numel(abort_vals);
    pct_succ = histcounts_fold_overflow(success_vals, edges) / max(n_succ, 1) * 100;
    pct_abort = histcounts_fold_overflow(abort_vals, edges) / max(n_abort, 1) * 100;

    hold on;
    plot(centers, pct_succ, '-o', 'LineWidth', 1.8, 'DisplayName', sprintf('Success (%d)', n_succ));
    plot(centers, pct_abort, '-s', 'LineWidth', 1.8, 'DisplayName', sprintf('Abort (%d)', n_abort));
    if cue_hold > 0
        xline(cue_hold, '--', 'Color', [0.4 0.4 0.4], 'LineWidth', 1.2, ...
            'HandleVisibility', 'off');
    end
    xline(theoretical_max, ':', 'Color', [0.5 0.5 0.5], 'LineWidth', 1.0, ...
        'HandleVisibility', 'off');
    xlabel('Time from CUE_ON (s)', 'FontWeight', 'bold', 'Interpreter', 'none');
    ylabel('% within cohort', 'FontWeight', 'bold');
    if isempty(success_vals)
        title(sprintf('Wait from cue  (abort %d)  cue=%.2f del=%.2f+%.2f', ...
            n_abort, cue_hold, del_hold, del_var), ...
            'FontWeight', 'bold', 'Interpreter', 'none');
    else
        title(sprintf('Wait from cue  (succ %d [%.2f-%.2f], abort %d)  cue=%.2f del=%.2f+%.2f', ...
            n_succ, min(success_vals), max(success_vals), n_abort, ...
            cue_hold, del_hold, del_var), ...
            'FontWeight', 'bold', 'Interpreter', 'none');
    end
    legend('Location', 'best');
    grid on;
    xlim([0, max_edge]);
end

function counts = histcounts_fold_overflow(vals, edges)
% histcounts; values > edges(end) added to last bin.
    counts = histcounts(vals, edges);
    if isempty(counts)
        return;
    end
    counts(end) = counts(end) + sum(vals > edges(end));
end

function [del_hold, del_var, cue_hold, cue_var] = delay_params_from_trials(trials_tbl)
    del_hold = NaN;
    del_var = NaN;
    cue_hold = NaN;
    cue_var = NaN;
    if isempty(trials_tbl) || height(trials_tbl) == 0
        return;
    end
    if ismember('DelTimeHold', trials_tbl.Properties.VariableNames)
        v = trials_tbl.DelTimeHold(~isnan(trials_tbl.DelTimeHold));
        if ~isempty(v), del_hold = v(1); end
    end
    if ismember('DelTimeHoldVar', trials_tbl.Properties.VariableNames)
        v = trials_tbl.DelTimeHoldVar(~isnan(trials_tbl.DelTimeHoldVar));
        if ~isempty(v), del_var = v(1); end
    end
    if ismember('CueTimeHold', trials_tbl.Properties.VariableNames)
        v = trials_tbl.CueTimeHold(~isnan(trials_tbl.CueTimeHold));
        if ~isempty(v), cue_hold = v(1); end
    end
    if ismember('CueTimeHoldVar', trials_tbl.Properties.VariableNames)
        v = trials_tbl.CueTimeHoldVar(~isnan(trials_tbl.CueTimeHoldVar));
        if ~isempty(v), cue_var = v(1); end
    end
end

function set_sgtitle_interpreter_none(fig)
    if isempty(fig) || ~ishghandle(fig)
        return;
    end
    layouts = findall(fig, 'Type', 'tiledlayout');
    for i = 1:numel(layouts)
        tl = layouts(i);
        if isprop(tl, 'Title') && ~isempty(tl.Title) && isprop(tl.Title, 'Interpreter')
            tl.Title.Interpreter = 'none';
        end
        if isprop(tl, 'Subtitle') && ~isempty(tl.Subtitle) && isprop(tl.Subtitle, 'Interpreter')
            tl.Subtitle.Interpreter = 'none';
        end
    end
end

function save_figure_pdf(fig, plot_path)
% Write PDF; if destination is locked (Acrobat/etc), write alongside then error clearly.
    tmp_path = [plot_path '.tmp.pdf'];
    try
        exportgraphics(fig, tmp_path, 'ContentType', 'vector');
    catch ME
        try
            print(fig, tmp_path, '-dpdf', '-vector');
        catch ME2
            if isfile(tmp_path), delete(tmp_path); end
            error('Failed to save PDF %s\nexportgraphics: %s\nprint: %s', ...
                plot_path, ME.message, ME2.message);
        end
    end
    if ~isfile(tmp_path)
        error('PDF was not written: %s', tmp_path);
    end
    try
        if isfile(plot_path)
            delete(plot_path);
        end
        movefile(tmp_path, plot_path, 'f');
    catch ME
        if isfile(tmp_path)
            alt = [plot_path(1:end-4) '_NEW.pdf'];
            movefile(tmp_path, alt, 'f');
            error(['Cannot overwrite locked PDF:\n  %s\n' ...
                'Close it in your PDF viewer and re-run.\n' ...
                'Wrote instead:\n  %s\n(%s)'], plot_path, alt, ME.message);
        end
        rethrow(ME);
    end
end


%% =============================================================================
% TIMING METRICS (successful trials only; STATE-aware)
%% =============================================================================

function kind = timing_metric_kind(field_name)
% 'RT' or 'MT' for plot titles (from column name).
    if strncmpi(char(field_name), 'MT', 2)
        kind = 'MT';
    else
        kind = 'RT';
    end
end

function report_invalid_timing_trials(trials_tbl, run_label, out_dir, run_base)
% Print + write successful trials missing any of the four timing metrics.
% File: <out_dir>/<run_base>_RT-MT_issues.text  (e.g. Fen2026-07-15_02_RT-MT_issues.text)
    fields = { ...
        'RTFixToSensorRelease', 'MTSensorToFixHold', ...
        'RTGoToMovement', 'MTMovementToTarget'};
    shorts = {'RT_fix', 'MT_fix', 'RT_go', 'MT_tar'};
    if isempty(trials_tbl) || height(trials_tbl) == 0
        return;
    end
    for f = 1:numel(fields)
        if ~ismember(fields{f}, trials_tbl.Properties.VariableNames)
            return;
        end
    end

    succ = trials_tbl.Success == 1;
    bad = succ & ( ...
        isnan(trials_tbl.RTFixToSensorRelease) | isnan(trials_tbl.MTSensorToFixHold) | ...
        isnan(trials_tbl.RTGoToMovement) | isnan(trials_tbl.MTMovementToTarget));
    n_succ = sum(succ);
    n_bad = sum(bad);

    lines = {};
    lines{end+1} = sprintf('RT/MT validity report  [%s]  run_base=%s', run_label, char(run_base)); %#ok<AGROW>
    if ismember('File', trials_tbl.Properties.VariableNames) && height(trials_tbl) > 0
        lines{end+1} = sprintf('File: %s', char(string(trials_tbl.File(1)))); %#ok<AGROW>
    end
    lines{end+1} = sprintf('Successful trials: %d', n_succ); %#ok<AGROW>

    if n_bad == 0
        lines{end+1} = sprintf('Timing OK: all %d successful trials have valid RT/MT', n_succ); %#ok<AGROW>
    else
        lines{end+1} = sprintf( ...
            'Timing issues: %d / %d successful trials missing valid RT/MT', ...
            n_bad, n_succ); %#ok<AGROW>
        idx = find(bad);
        for k = 1:numel(idx)
            i = idx(k);
            miss = shorts(isnan([ ...
                trials_tbl.RTFixToSensorRelease(i), trials_tbl.MTSensorToFixHold(i), ...
                trials_tbl.RTGoToMovement(i), trials_tbl.MTMovementToTarget(i)]));
            hand = char(trials_tbl.Hand(i));
            task = char(trials_tbl.TaskType(i));
            if strlength(string(hand)) == 0, hand = '?'; end
            if strlength(string(task)) == 0, task = '?'; end
            lines{end+1} = sprintf('  trial %d  hand=%s  task=%s  missing: %s', ...
                trials_tbl.Trial(i), hand, task, strjoin(miss, ', ')); %#ok<AGROW>
        end
    end

    for i = 1:numel(lines)
        fprintf('  %s\n', lines{i});
    end

    if nargin < 4 || isempty(out_dir) || isempty(run_base)
        return;
    end
    report_path = fullfile(char(out_dir), sprintf('%s_RT-MT_issues.text', char(run_base)));
    fid = fopen(report_path, 'w');
    if fid < 0
        warning('ma1:TimingReportWriteFailed', 'Could not write %s', report_path);
        return;
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    for i = 1:numel(lines)
        fprintf(fid, '%s\n', lines{i});
    end
    fprintf('  Wrote %s\n', report_path);
end

function [rt_fix_sensor, mt_sensor_fix, rt_go_move, mt_move_target] = get_trial_timing_metrics(trial, STATE)
% Four latencies for one successful trial (NaN if a stage cannot be detected).
%
% FIXATION epoch:
%   RTFixToSensorRelease = FIX_ACQ onset -> home-sensor release
%   MTSensorToFixHold    = sensor release -> FIX_HOL onset
% REACH epoch:
%   RTGoToMovement       = TAR_ACQ (Go) -> hand leaves screen fixation
%   MTMovementToTarget   = speed onset near fixation (else detach) -> TAR_HOL
%
% Shared event times are cached once so sensor/Go lookups are not repeated.
    cache = struct();
    cache.t_fix_acq = get_fix_acq_onset(trial, STATE);
    cache.t_fix_hol = get_state_event_onset(trial, STATE.FIX_HOL);
    cache.t_go = get_go_cue_onset(trial, STATE);
    cache.t_release = get_sensor_release_time(trial, cache.t_fix_acq, cache.t_fix_hol, STATE);

    rt_fix_sensor = get_rt_fix_to_sensor_release_cached(trial, STATE, cache);
    mt_sensor_fix = get_mt_sensor_to_fix_hold_cached(trial, STATE, cache);
    [rt_go_move, mt_move_target] = get_reach_epoch_timing_cached(trial, STATE, cache);
end

function rt_fix = get_rt_fix_to_sensor_release_cached(~, ~, cache)
    rt_fix = NaN;
    cfg = get_timing_detection_config();
    if ~isnan(cache.t_fix_acq) && ~isnan(cache.t_release)
        rt_fix = sanitize_latency(cache.t_release - cache.t_fix_acq, cfg.min_rt_fix, cfg.max_rt_fix);
    end
end

function mt_fix = get_mt_sensor_to_fix_hold_cached(~, ~, cache)
    mt_fix = NaN;
    cfg = get_timing_detection_config();
    if ~isnan(cache.t_release) && ~isnan(cache.t_fix_hol)
        mt_fix = sanitize_latency(cache.t_fix_hol - cache.t_release, cfg.min_mt_fix, cfg.max_mt_fix);
    end
end

function [rt_go, mt_target] = get_reach_epoch_timing_cached(trial, STATE, cache)
    rt_go = NaN;
    mt_target = NaN;
    cfg = get_timing_detection_config();
    if isnan(cache.t_go)
        return;
    end
    t_detach = get_fixation_detach_time(trial, cache.t_go, STATE);
    if isnan(t_detach)
        return;
    end
    rt_go = sanitize_latency(t_detach - cache.t_go, cfg.min_rt_go, cfg.max_rt_go);
    if isnan(rt_go)
        return;
    end
    t_mt_start = detect_speed_onset_near_fixation(trial, cache.t_go, cfg, STATE);
    if isnan(t_mt_start)
        t_mt_start = t_detach;
    end
    mt_target = get_mt_movement_to_target(trial, t_mt_start, STATE);
end

function mt_target = get_mt_movement_to_target(trial, t_move_start, STATE)
    mt_target = NaN;
    if isnan(t_move_start)
        return;
    end
    t_target = get_target_hold_onset_time(trial, t_move_start, STATE);
    if isnan(t_target)
        return;
    end
    cfg = get_timing_detection_config();
    mt_target = sanitize_latency(t_target - t_move_start, cfg.min_mt_target, cfg.max_mt_target);
end

function cfg = get_timing_detection_config()
    cfg.min_rt_fix = 0.05;
    cfg.max_rt_fix = 5.0;
    cfg.min_mt_fix = 0.01;
    cfg.max_mt_fix = 5.0;
    cfg.min_rt_go = 0.05;
    cfg.max_rt_go = 2.0;
    cfg.pre_go_baseline_win = 0.10;
    cfg.fix_exit_radius = 1.2;
    cfg.move_onset_speed_abs = 400;
    cfg.move_onset_speed_margin = 150;
    cfg.move_onset_max_disp = 2.0;
    cfg.min_mt_target = 0.10;
    cfg.max_mt_target = 2.0;
    cfg.target_hold_window = 0.05;
    cfg.target_acq_radius = 5;
    cfg.target_sustain_samples = 3;
end

function val = sanitize_latency(val, min_val, max_val)
    if isnan(val) || val < min_val || val > max_val
        val = NaN;
    end
end

function t_fix_acq = get_fix_acq_onset(trial, STATE)
    t_fix_acq = NaN;
    if ~isfield(trial, 'states') || ~isfield(trial, 'states_onset')
        return;
    end
    states = trial.states(:);
    onsets = trial.states_onset(:);
    idx_tar = find(states == STATE.TAR_ACQ, 1, 'first');
    if isempty(idx_tar)
        idx_fix = find(states == STATE.FIX_ACQ);
    else
        idx_fix = find(states == STATE.FIX_ACQ & (1:numel(states))' < idx_tar);
    end
    if ~isempty(idx_fix)
        t_fix_acq = onsets(idx_fix(end));
    end
end

function t_go = get_go_cue_onset(trial, STATE)
    t_go = get_state_event_onset(trial, STATE.TAR_ACQ);
end

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
end

function t_release = get_sensor_release_time(trial, t_after, t_before, STATE)
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
    t = align_tsample_to_state_time(trial, t, STATE);
    rel_candidates = find(sen(1:end-1) > 0.5 & sen(2:end) <= 0.5);
    for k = 1:numel(rel_candidates)
        rel_idx = rel_candidates(k);
        t_rel = t(rel_idx + 1);
        if t_rel >= t_after && (isnan(t_before) || t_rel <= t_before)
            t_release = t_rel;
            return;
        end
    end
end

function t_aligned = align_tsample_to_state_time(trial, t, STATE)
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
        if ~isempty(STATE)
            anchor_codes = [STATE.TAR_ACQ, STATE.FIX_ACQ, STATE.FIX_HOL, STATE.TAR_HOL];
        else
            anchor_codes = [];
        end
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
end

function [t, x, y, state] = get_aligned_hand_kinematics(trial, STATE)
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
    t = align_tsample_to_state_time(trial, t(1:n), STATE);
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
end

function [xh, yh] = get_target_hold_position(trial, STATE)
    xh = NaN;
    yh = NaN;
    cfg = get_timing_detection_config();
    [t, x, y, state] = get_aligned_hand_kinematics(trial, STATE);
    if isempty(t)
        return;
    end

    hold_mask = [];
    if ~isempty(state)
        hold_mask = state == STATE.TAR_HOL;
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
end

function t_detach = get_fixation_detach_time(trial, t_go, STATE)
    t_detach = NaN;
    if ~isfield(trial, 'x_hnd') || ~isfield(trial, 'y_hnd') || ~isfield(trial, 'tSample_from_time_start')
        return;
    end
    if isnan(t_go)
        return;
    end
    t_detach = detect_fixation_detach_after_go(trial, t_go, get_timing_detection_config(), STATE);
end

function t_on = detect_speed_onset_near_fixation(trial, t_go, cfg, STATE)
    t_on = NaN;
    [t, x, y, ~] = get_aligned_hand_kinematics(trial, STATE);
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
    t_tar_hol = get_state_event_onset(trial, STATE.TAR_HOL);
    if ~isnan(t_tar_hol)
        t_latest = min(t_latest, t_tar_hol);
    end

    idx = find(t >= t_earliest & t <= t_latest & ...
        spd >= speed_thr & dist < cfg.move_onset_max_disp, 1, 'first');
    if ~isempty(idx)
        t_on = t(idx);
    end
end

function t_detach = detect_fixation_detach_after_go(trial, t_go, cfg, STATE)
    t_detach = NaN;
    [t, x, y, ~] = get_aligned_hand_kinematics(trial, STATE);
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
    t_tar_hol = get_state_event_onset(trial, STATE.TAR_HOL);
    if ~isnan(t_tar_hol)
        t_latest = min(t_latest, t_tar_hol);
    end

    idx = find(t >= t_earliest & t <= t_latest & ...
        hypot(x - x0, y - y0) >= cfg.fix_exit_radius, 1, 'first');
    if ~isempty(idx)
        t_detach = t(idx);
    end
end

function t_target = get_target_hold_onset_time(trial, t_detach, STATE)
    t_target = NaN;
    if isnan(t_detach)
        return;
    end

    t_tar_hol = get_state_event_onset(trial, STATE.TAR_HOL);
    if ~isnan(t_tar_hol) && t_tar_hol >= t_detach
        t_target = t_tar_hol;
        return;
    end

    t_target = get_kinematic_target_arrival_time(trial, t_detach, STATE);
end

function t_target = get_kinematic_target_arrival_time(trial, t_detach, STATE)
    t_target = NaN;
    if isnan(t_detach) || ~isfield(trial, 'x_hnd') || ~isfield(trial, 'y_hnd')
        return;
    end

    cfg = get_timing_detection_config();
    [xh, yh] = get_target_hold_position(trial, STATE);
    if isnan(xh) || isnan(yh)
        return;
    end

    [t, x, y, ~] = get_aligned_hand_kinematics(trial, STATE);
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
end

%% =============================================================================
% RUN DISCOVERY, PATH INFERENCE, SKIP LIST
%% =============================================================================

function out_dir = ensure_output_dir(output_dir)
% Create output_dir (and parents) if needed; return char path.
    out_dir = char(output_dir);
    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end
end

function session_folder = infer_session_folder_name(input_path)
% Leaf folder name for the session, taken from input_path.
%   Y:\Data\Feno\20260715              -> 20260715
%   Y:\Data\Feno\20260715\run_01.mat   -> 20260715
    input_path = char(input_path);
    if isfolder(input_path)
        session_dir = input_path;
    elseif isfile(input_path)
        session_dir = fileparts(input_path);
    else
        % Path may not exist yet / Dropbox offline — still use folder parts.
        [parent, name, ext] = fileparts(input_path);
        if isempty(ext)
            session_dir = input_path;
        else
            session_dir = parent;
        end
    end
    session_dir = char(session_dir);
    while ~isempty(session_dir) && (session_dir(end) == filesep || session_dir(end) == '/' || session_dir(end) == '\')
        session_dir = session_dir(1:end-1);
    end
    [~, session_folder] = fileparts(session_dir);
    if isempty(session_folder)
        error('Could not infer session folder name from input_path: %s', input_path);
    end
end

function [run_files, skipped_user_runs] = apply_skip_runs(run_files, skip_runs)
    skipped_user_runs = {};
    if isempty(skip_runs)
        return;
    end
    if ischar(skip_runs)
        skip_runs = {skip_runs};
    elseif isstring(skip_runs)
        skip_runs = cellstr(skip_runs);
    elseif isnumeric(skip_runs)
        skip_runs = num2cell(skip_runs(:));
    end

    skip_mask = false(size(run_files));
    for k = 1:numel(skip_runs)
        item = skip_runs{k};
        if isnumeric(item)
            idx = round(item(1));
            if idx >= 1 && idx <= numel(run_files)
                skip_mask(idx) = true;
                skipped_user_runs{end+1} = run_files{idx}; %#ok<AGROW>
            end
        else
            base = char(item);
            for j = 1:numel(run_files)
                [~, fname, ~] = fileparts(run_files{j});
                if strcmp(fname, base) || strcmp(run_files{j}, base)
                    skip_mask(j) = true;
                    skipped_user_runs{end+1} = run_files{j}; %#ok<AGROW>
                end
            end
        end
    end
    run_files = run_files(~skip_mask);
    skipped_user_runs = unique(skipped_user_runs, 'stable');
end

function run_files = list_day_runs(input_path)
    input_path = char(input_path);
    if isfile(input_path)
        run_files = {input_path};
        return;
    end
    if isfolder(input_path)
        day_dir = input_path;
    else
        [parent, ~, ext] = fileparts(input_path);
        if isempty(ext)
            day_dir = input_path;
        else
            day_dir = parent;
        end
    end
    d = dir(fullfile(day_dir, '*.mat'));
    if isempty(d)
        run_files = {};
        return;
    end
    [~, idx] = sort({d.name});
    d = d(idx);
    run_files = fullfile({d.folder}, {d.name});
end

function trials = filter_reach_trials(trials)
    if isempty(trials)
        return;
    end
    keep = false(numel(trials), 1);
    for i = 1:numel(trials)
        keep(i) = ~is_eye_calibration_trial(trials(i));
    end
    trials = trials(keep);
end

function tf = all_eye_calibration_trials(trials)
    tf = false;
    if isempty(trials)
        return;
    end
    tf = true;
    for i = 1:numel(trials)
        if ~is_eye_calibration_trial(trials(i))
            tf = false;
            return;
        end
    end
end

function tf = is_eye_calibration_trial(trial)
% Eye calibration: effector==0 only (type==1 alone is fixation, not eye-cal).
    tf = false;
    if isempty(trial) || ~isstruct(trial)
        return;
    end
    effector = get_scalar_num_field(trial, 'effector');
    tf = ~isnan(effector) && effector == 0;
end

function animal_name = infer_animal_name(input_path)
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

    input_path = char(input_path);
    if isfolder(input_path)
        folder = input_path;
    elseif isfile(input_path)
        folder = fileparts(input_path);
    else
        [parent, name, ext] = fileparts(input_path);
        if isempty(ext)
            folder = input_path;
        else
            folder = parent;
        end
    end
    [parent_path, leaf] = fileparts(folder);
    if looks_like_date_folder(leaf) && ~isempty(parent_path)
        [~, animal_name] = fileparts(parent_path);
    else
        animal_name = leaf;
    end
    if isempty(animal_name)
        animal_name = 'unknown';
    end
end

function tf = looks_like_date_folder(name)
    name = char(name);
    tf = ~isempty(regexp(name, '^\d{8}$', 'once')) || ...
        ~isempty(regexp(name, '^\d{4}-\d{2}-\d{2}$', 'once'));
end

function animal_name = parse_animal_from_run_filename(run_file)
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
end

function session_date = infer_session_date(input_path, run_files)
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
        error('Could not infer session date from input_path or run filenames.');
    end
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
end

function session_date = parse_session_date_from_path(input_path)
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
end

%% =============================================================================
% TRIAL FIELD HELPERS
%% =============================================================================

function position = get_target_pos(trial)
    position = NaN;
    if isfield(trial, 'hnd') && isfield(trial.hnd, 'tar') && isfield(trial.hnd, 'fix') && ...
       isfield(trial.hnd.fix, 'x')
        if numel(trial.hnd.tar) == 1 && isfield(trial.hnd.tar, 'x')
            tar_x = trial.hnd.tar.x;
        elseif isfield(trial, 'target_selected') && numel(trial.target_selected) >= 2 && ...
               ~isnan(trial.target_selected(2))
            tar_x = trial.hnd.tar(trial.target_selected(2)).x;
        else
            return;
        end
        if tar_x < trial.hnd.fix.x
            position = 1;
        elseif tar_x > trial.hnd.fix.x
            position = 2;
        end
    end
end

function tf = trial_reached_fixation(trial, STATE)
    tf = false;
    if ~isfield(trial, 'states') || isempty(trial.states)
        return;
    end
    states = trial.states(:);
    tf = any(states == STATE.FIX_ACQ) || any(states == STATE.FIX_HOL);
end

function tf = trial_cue_or_target_shown(trial, STATE)
    tf = false;
    if ~isfield(trial, 'states') || isempty(trial.states)
        return;
    end
    states = trial.states(:);
    tf = any(ismember(states, [STATE.CUE_ON, STATE.DEL_PER, STATE.TAR_ACQ, STATE.TAR_HOL]));
    if ~tf
        tf = ~isnan(get_target_pos(trial));
    end
end

function [del_hold, del_var, cue_hold, cue_var] = get_delay_timing_params(data, trials)
    del_hold = NaN;
    del_var = NaN;
    cue_hold = NaN;
    cue_var = NaN;
    candidates = {};
    if isfield(data, 'task') && isstruct(data.task) && isfield(data.task, 'timing')
        candidates{end+1} = data.task.timing; %#ok<AGROW>
    end
    for i = 1:min(numel(trials), 20)
        if isfield(trials(i), 'task') && isstruct(trials(i).task) && isfield(trials(i).task, 'timing')
            candidates{end+1} = trials(i).task.timing; %#ok<AGROW>
            break;
        end
    end
    for i = 1:numel(candidates)
        tim = candidates{i};
        if isfield(tim, 'del_time_hold')
            del_hold = double(tim.del_time_hold(1));
        end
        if isfield(tim, 'del_time_hold_var')
            del_var = double(tim.del_time_hold_var(1));
        end
        if isfield(tim, 'cue_time_hold')
            cue_hold = double(tim.cue_time_hold(1));
        end
        if isfield(tim, 'cue_time_hold_var')
            cue_var = double(tim.cue_time_hold_var(1));
        end
        if ~isnan(del_hold) || ~isnan(cue_hold)
            if isnan(del_var), del_var = 0; end
            if isnan(cue_var), cue_var = 0; end
            return;
        end
    end
end

function reason = get_abort_reason(tr)
    reason = '';
    candidate_fields = {'abort_code', 'abortCode', 'abort_reason', 'abortReason', 'aborted_reason', ...
        'error', 'error_code', 'errorCode', 'fail_reason', 'failReason'};
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
end

function paradigm = get_reach_paradigm_type(data, trials)
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
end

function paradigm = effector_to_paradigm_label(effector)
    paradigm = "";
    if isnan(effector)
        return;
    end
    if ismember(effector, [1, 6])
        paradigm = "direct reaches";
    elseif effector == 4
        paradigm = "dissociated reaches";
    end
end

function v = get_scalar_num_field(tr, fieldname)
    v = NaN;
    if ~isfield(tr, fieldname)
        return;
    end
    val = tr.(fieldname);
    if isempty(val) || ~isnumeric(val)
        return;
    end
    v = val(1);
end

function pct = safe_pct(x, n)
    if n > 0
        pct = x / n * 100;
    else
        pct = NaN;
    end
end

%% =============================================================================
% TABLE TEMPLATES
%% =============================================================================

function tbl = empty_trial_table()
    tbl = table( ...
        string([]), int32([]), int32([]), string([]), ...
        string([]), double([]), double([]), double([]), double([]), double([]), double([]), ...
        string([]), string([]), double([]), string([]), double([]), double([]), double([]), ...
        double([]), double([]), double([]), double([]), double([]), double([]), ...
        'VariableNames', { ...
            'Condition', 'Run', 'Trial', 'File', 'TaskType', 'DelayDuration', 'TargetAcqTime', ...
            'RTFixToSensorRelease', 'MTSensorToFixHold', 'RTGoToMovement', 'MTMovementToTarget', ...
            'Target', 'Hand', 'Success', 'reason_of_abort', 'TimeUntilAbort', ...
            'DelayForHist', 'AbortAfterCue', 'FixHandKnown', 'CueSpaceAssignable', ...
            'DelTimeHold', 'DelTimeHoldVar', 'CueTimeHold', 'CueTimeHoldVar'});
end

function run_tbl = empty_run_summary_table(condition_label, run_index, filepath)
    run_tbl = table( ...
        string(condition_label), run_index, string(filepath), "", 0, 0, 0, 0, ...
        NaN, NaN, NaN, ...
        0, 0, 0, 0, ...
        0, 0, 0, 0, ...
        0, 0, 0, 0, ...
        0, 0, NaN, ...
        0, 0, NaN, ...
        0, 0, NaN, ...
        0, 0, NaN, ...
        0, 0, 0, 0, 0, ...
        NaN, NaN, ...
        'VariableNames', { ...
            'Condition', 'Run', 'File', 'ReachParadigm', 'AllTrials', 'InitiatedTrials', 'SuccessfulTrials', 'FailedTrials', ...
            'PctInitiatedOfAll', 'PctSuccessfulOfAll', 'PctSuccessfulOfInitiated', ...
            'LeftHandAll', 'RightHandAll', 'LeftTargets', 'RightTargets', ...
            'Instr_LL', 'Instr_LR', 'Instr_RL', 'Instr_RR', ...
            'Free_LL', 'Free_LR', 'Free_RL', 'Free_RR', ...
            'FreeLeftTotal', 'FreeLeftSuccess', 'FreeLeftSuccessPct', ...
            'FreeRightTotal', 'FreeRightSuccess', 'FreeRightSuccessPct', ...
            'InstrLeftTotal', 'InstrLeftSuccess', 'InstrLeftSuccessPct', ...
            'InstrRightTotal', 'InstrRightSuccess', 'InstrRightSuccessPct', ...
            'abort_use_incorrect_hand', 'abort_hnd_fix_acq_state', 'abort_hnd_del_per_state', ...
            'abort_hnd_tar_acq_state', 'abort_hnd_fix_hold_state', ...
            'DelTimeHold', 'DelTimeHoldVar'});
end

%% =============================================================================
% EXCEL EXPORT
%% =============================================================================

function write_tables_to_excel(excel_path, run_tbls, run_trials_tbls, day_tbl, day_trials_tbl)
    if exist(excel_path, 'file')
        delete(excel_path);
    end

    writetable(day_tbl, excel_path, 'Sheet', 'day_general');
    writetable(day_trials_tbl, excel_path, 'Sheet', 'day_all_data');

    n_runs = numel(run_tbls);
    for k = 1:n_runs
        writetable(run_tbls{k}, excel_path, 'Sheet', sprintf('run%d_general', k));
        writetable(run_trials_tbls{k}, excel_path, 'Sheet', sprintf('run%d_all_data', k));
    end
end
