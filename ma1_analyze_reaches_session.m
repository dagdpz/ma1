function out = ma1_analyze_reaches_session(input_path, output_base, varargin)
% ma1_analyze_reaches_session - Daily hand-reach session analysis (tables, plots, Excel).
%
% Pipeline: setup -> resolve out_dir -> discover runs -> one-load analyze -> day tables
%           -> 3x4 PDF figures (per-run; combined if n_runs>1) -> optional Excel -> out struct.
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
%   out = ma1_analyze_reaches_session(input_path, output_base, 'name', value, ...);
%
% Example:
%   out = ma1_analyze_reaches_session( ...
%       'Y:\Data\Feno\20260715', ...
%       'Y:\Projects\dPul-MIP\Feno\Behavior_analysis\');
%   out = ma1_analyze_reaches_session( ...
%       'Y:\Data\Feno\20260818', ...
%       'Y:\Projects\dPul-MIP\Feno\Behavior_analysis\', ...
%       'keep_runs', [2 3], 'write_excel', false);
%   % keep Fen*_02.mat + *_03.mat (filename _xx, not folder order)
%   % combined PDFs (n_runs>1): Fen_2026-08-18_02-03.pdf  (session: bars + per-run mean dots)
%   out = ma1_analyze_reaches_session( ...
%       'Y:\Data\Feno\20260819', ...
%       'Y:\Projects\dPul-MIP\Feno\Behavior_analysis\', ...
%       'keep_runs', [1 3], 'write_excel', false, 'pool_runs', true);
%   % pool: all trials as one run (trial dots, no run-mean dots)
%   out = ma1_analyze_reaches_session( ...
%       'Y:\Data\Feno\20260819', ...
%       'Y:\Projects\dPul-MIP\Feno\Behavior_analysis\', ...
%       'skip_runs', 1, 'write_excel', false);
%
% Inputs:
%   input_path   - day folder OR a single .mat (only that file if a file)
%   output_base  - analysis root; session leaf from input_path -> out_dir
% Optional name/value, defaults:
%   keep_runs    = []        keep all *_xx.mat. Override: 2, [2 3], '02', '02-03'
%   skip_runs    = []        skip none.         Override: 1, [1 3], '01', '01-03'
%   write_excel  = true
%   pool_runs    = false     if true and n_runs>1, combined PDFs plot all trials as one run
%                            (not session run-averages)
%
% Output (struct out): animal_name, session_date, session_folder, output_base, out_dir,
%   run_files, n_runs, run_tag, keep_runs, skipped_calibration_runs, skipped_user_runs, write_excel,
%   excel_fullpath, plot_files, error_plot_files, run_tables, day_table, run_trials_tables, day_trials_table,
%   pool_runs
%
% Figures (tiledlayout 3x4): row1 instr success / free-choice share / uncrossed;
%   row2 four RT/MT panels; row3 RT-vs-trial + wait-from-cue hist + success counts at targets.
% Extra errors PDF (2x5): abort-state % + abort times for this task's mid-sequence only
%   (type 2 = FIX/TAR, no CUE/DEL); lower = endpoints for states the task actually has.
%   lower = endpoints vs windows (eye orange, hand windows dark yellow, LH/RH traces blue/green):
%   success FIX_HOL/TAR_HOL means; abort pre→post for FIX / CUE+DEL / TAR.
% DelayForHist is ALWAYS from CUE_ON onset (success = cue+delay; abort = cue→abort).
% Panel 2 = instructed hand×space only (Free success-by-chosen-space omitted).

    t_wall = tic;
    prevWarn = warning('query', 'MATLAB:xlswrite:AddSheet');
    warning('off', 'MATLAB:xlswrite:AddSheet');
    c = onCleanup(@() warning(prevWarn));

    dict = get_task_state_dict();
    STATE = dict.STATE;

    if nargin < 1 || isempty(input_path)
        error('Input path is required (file or folder).');
    end
    if nargin < 2 || isempty(output_base)
        error('Output base path is required.');
    end

    param.keep_runs = [];       % keep all
    param.skip_runs = [];       % skip none
    param.write_excel = true;
    param.pool_runs = false;
    if nargin > 2
        param = apply_name_value_pairs(param, varargin);
    end
    keep_runs = param.keep_runs;
    write_excel = param.write_excel;
    skip_runs = param.skip_runs;
    pool_runs = param.pool_runs;
    if ~islogical(write_excel) || ~isscalar(write_excel)
        error('write_excel must be a scalar logical.');
    end
    if ~islogical(pool_runs) || ~isscalar(pool_runs)
        error('pool_runs must be a scalar logical.');
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
        fprintf('Skipped by skip_runs (%d):\n', numel(skipped_user_runs));
        for i = 1:numel(skipped_user_runs)
            fprintf('  - %s\n', skipped_user_runs{i});
        end
    end
    [run_candidates, keep_ids] = apply_keep_runs(run_candidates, keep_runs);
    if ~isempty(keep_ids)
        fprintf('keep_runs _xx filter: %s\n', format_run_id_list(keep_ids));
    end
    fprintf('Candidates after keep/skip: %d\n', numel(run_candidates));
    if isempty(run_candidates)
        error('No .mat files found after keep_runs/skip_runs.');
    end

    % One load per candidate: non-reach runs skipped inside process_single_run.
    t_read = tic;
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
            fprintf('  -> non-reach (eye-cal / fixation) — skipped  [%.1f s]\n', ...
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
        fprintf('Skipped non-reach runs: %d\n', numel(skipped_calibration_runs));
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
    run_tag = format_run_suffix_tag(run_files);
    excel_fullpath = fullfile(out_dir, sprintf('%s_%s_%s.xlsx', animal_name, date_str, run_tag));

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
    t_read_s = toc(t_read);

    write_session_pdfs = (n_runs > 1) && ~pool_runs;
    write_pooled_pdfs = (n_runs > 1) && pool_runs;
    if pool_runs && n_runs == 1
        fprintf('pool_runs ignored (n_runs=1; already run-style)\n');
    elseif write_pooled_pdfs
        fprintf('Pooling %d runs as one run-style figure (all trials concatenated)\n', n_runs);
    end
    n_pdf = n_runs + double(write_session_pdfs) + double(write_pooled_pdfs);
    plot_files = cell(n_pdf, 1);
    error_plot_files = cell(n_pdf, 1);
    t_fig = tic;
    for k = 1:n_runs
        [~, run_base, ~] = fileparts(run_files{k});
        plot_files{k} = make_run_figure(run_trials_tbls{k}, out_dir, run_base);
        error_plot_files{k} = make_error_figure( ...
            run_trials_tbls{k}, {}, false, out_dir, [run_base '_errors'], ...
            sprintf('Errors: %s', run_base));
    end
    combined_base = sprintf('%s_%s_%s', animal_name, date_str, run_tag);
    if write_session_pdfs
        session_title = sprintf('%s %s (runs %s)', animal_name, date_str, run_tag);
        error_plot_files{end} = make_error_figure( ...
            day_trials_tbl, run_trials_tbls, true, out_dir, ...
            [combined_base '_errors'], ...
            sprintf('%s errors', session_title));
        plot_files{end} = make_session_figure( ...
            day_trials_tbl, run_trials_tbls, out_dir, ...
            combined_base, session_title);
    elseif write_pooled_pdfs
        pooled_title = sprintf('%s %s pooled (runs %s)', animal_name, date_str, run_tag);
        error_plot_files{end} = make_error_figure( ...
            day_trials_tbl, {}, false, out_dir, ...
            [combined_base '_errors'], ...
            sprintf('%s errors', pooled_title));
        plot_files{end} = make_run_figure( ...
            day_trials_tbl, out_dir, combined_base, pooled_title);
    end
    t_fig_s = toc(t_fig);

    t_xls_s = 0;
    if write_excel
        t_xls = tic;
        write_tables_to_excel(excel_fullpath, run_tbls, run_trials_tbls, ...
            day_tbl, day_trials_tbl);
        t_xls_s = toc(t_xls);
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
    out.run_tag = run_tag;
    out.keep_runs = keep_runs;
    out.pool_runs = pool_runs;
    out.skipped_calibration_runs = skipped_calibration_runs;
    out.skipped_user_runs = skipped_user_runs;
    out.write_excel = write_excel;
    out.excel_fullpath = excel_fullpath;
    out.out_dir = out_dir;
    out.plot_files = plot_files;
    out.error_plot_files = error_plot_files;
    out.run_tables = run_tbls;
    out.day_table = day_tbl;
    out.run_trials_tables = run_trials_tbls;
    out.day_trials_table = day_trials_tbl;

    fprintf('\nAnalysis complete successfully, data saved in %s\n', out_dir);
    fprintf('=== Timing ===\n');
    fprintf('  read/analyze   %6.1f s\n', t_read_s);
    fprintf('  figures/PDF    %6.1f s\n', t_fig_s);
    if write_excel
        fprintf('  excel          %6.1f s\n', t_xls_s);
    end
    fprintf('  total          %6.1f s\n', toc(t_wall));
end

%% =============================================================================
% SINGLE-RUN PROCESSING
%% =============================================================================

function [trials_tbl, summary_tbl, is_cal] = process_single_run(filepath, run_index, condition_label, STATE)
% One .mat load -> trial table + one-row run summary.
% is_cal=true (skip run) if all trials are non-reach (effector==0 or fixation type).

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

    if all_nonreach_trials(data.trial)
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
        is_cal = true;
        trials_tbl = empty_trial_table();
        summary_tbl = empty_run_summary_table(condition_label, run_index, filepath);
        return;
    end

    condition_col = repmat(string(condition_label), n_trials, 1);
    run_col = repmat(int32(run_index), n_trials, 1);
    trial_col = int32((1:n_trials)');
    file_col = repmat(string(filepath), n_trials, 1);
    task_type_col = repmat("", n_trials, 1);
    mp_type_col = NaN(n_trials, 1);
    tar_x_col = NaN(n_trials, 1);
    tar_y_col = NaN(n_trials, 1);
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
    aborted_state_col = NaN(n_trials, 1);
    aborted_state_dur_col = NaN(n_trials, 1);
    eye_fix_mx = NaN(n_trials, 1); eye_fix_my = NaN(n_trials, 1);
    hnd_fix_mx = NaN(n_trials, 1); hnd_fix_my = NaN(n_trials, 1);
    eye_tar_mx = NaN(n_trials, 1); eye_tar_my = NaN(n_trials, 1);
    hnd_tar_mx = NaN(n_trials, 1); hnd_tar_my = NaN(n_trials, 1);
    eye_pre_x = NaN(n_trials, 1); eye_pre_y = NaN(n_trials, 1);
    hnd_pre_x = NaN(n_trials, 1); hnd_pre_y = NaN(n_trials, 1);
    eye_post_x = NaN(n_trials, 1); eye_post_y = NaN(n_trials, 1);
    hnd_post_x = NaN(n_trials, 1); hnd_post_y = NaN(n_trials, 1);
    win_eye_fix_x = NaN(n_trials, 1); win_eye_fix_y = NaN(n_trials, 1); win_eye_fix_r = NaN(n_trials, 1);
    win_hnd_fix_x = NaN(n_trials, 1); win_hnd_fix_y = NaN(n_trials, 1); win_hnd_fix_r = NaN(n_trials, 1);
    win_eye_tar_x = NaN(n_trials, 1); win_eye_tar_y = NaN(n_trials, 1); win_eye_tar_r = NaN(n_trials, 1);
    win_hnd_tar_x = NaN(n_trials, 1); win_hnd_tar_y = NaN(n_trials, 1); win_hnd_tar_r = NaN(n_trials, 1);
    win_eye_tar2_x = NaN(n_trials, 1); win_eye_tar2_y = NaN(n_trials, 1); win_eye_tar2_r = NaN(n_trials, 1);
    win_hnd_tar2_x = NaN(n_trials, 1); win_hnd_tar2_y = NaN(n_trials, 1); win_hnd_tar2_r = NaN(n_trials, 1);
    win_hnd_cue_x = NaN(n_trials, 1); win_hnd_cue_y = NaN(n_trials, 1); win_hnd_cue_r = NaN(n_trials, 1);
    win_hnd_cue2_x = NaN(n_trials, 1); win_hnd_cue2_y = NaN(n_trials, 1); win_hnd_cue2_r = NaN(n_trials, 1);

    S = init_run_summary_counters(n_trials);

    for i = 1:n_trials
        trial = trials(i);

        choice = get_scalar_num_field(trial, 'choice');
        if choice == 1
            task_type_col(i) = "Free";
        elseif choice == 0
            task_type_col(i) = "Instructed";
        end
        mp_type_col(i) = get_scalar_num_field(trial, 'type');

        t_al = get_aligned_sample_time(trial, STATE);
        [delay_col(i), target_acq_time_col(i)] = get_delay_and_target_acq(trial, STATE);

        success_col(i) = get_scalar_num_field(trial, 'success');
        if isnan(success_col(i))
            success_col(i) = 0;
        end
        if success_col(i) == 1
            S.successful_trials = S.successful_trials + 1;
            [rt_fix_sensor_col(i), mt_sensor_fix_col(i), rt_go_move_col(i), mt_move_target_col(i)] = ...
                get_trial_timing_metrics(trial, STATE, t_al);
        else
            S.failed_trials = S.failed_trials + 1;
        end

        [target_pos, tar_x_col(i), tar_y_col(i)] = get_target_pos(trial);
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
        % Target L/R already implies cue/target geometry; state scan was redundant.
        cue_space_assignable_col(i) = double( ...
            ismember(choice, [0, 1]) && ismember(rh, [1, 2]) && ismember(target_pos, [1, 2]));

        aborted_state = NaN;
        abr_dur = NaN;
        if success_col(i) == 0
            reason = get_abort_reason(trial);
            if strlength(string(reason)) > 0
                abort_reason_col(i) = string(lower(reason));
            end
            aborted_state = get_trial_aborted_state(trial, STATE);
            abr_dur = get_aborted_state_duration(trial);
            [abort_after_cue_col(i), delay_for_hist_col(i), time_until_abort_col(i)] = ...
                compute_delay_hist_fields(trial, success_col(i), STATE, delay_col(i), reason, aborted_state);
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

        sp = get_trial_spatial_metrics(trial, STATE, t_al, aborted_state, abr_dur);
        aborted_state_col(i) = sp.AbortedState;
        aborted_state_dur_col(i) = sp.AbortedStateDuration;
        eye_fix_mx(i) = sp.EyeFixMeanX; eye_fix_my(i) = sp.EyeFixMeanY;
        hnd_fix_mx(i) = sp.HndFixMeanX; hnd_fix_my(i) = sp.HndFixMeanY;
        eye_tar_mx(i) = sp.EyeTarMeanX; eye_tar_my(i) = sp.EyeTarMeanY;
        hnd_tar_mx(i) = sp.HndTarMeanX; hnd_tar_my(i) = sp.HndTarMeanY;
        eye_pre_x(i) = sp.EyeAbortPreX; eye_pre_y(i) = sp.EyeAbortPreY;
        hnd_pre_x(i) = sp.HndAbortPreX; hnd_pre_y(i) = sp.HndAbortPreY;
        eye_post_x(i) = sp.EyeAbortPostX; eye_post_y(i) = sp.EyeAbortPostY;
        hnd_post_x(i) = sp.HndAbortPostX; hnd_post_y(i) = sp.HndAbortPostY;
        win_eye_fix_x(i) = sp.WinEyeFixX; win_eye_fix_y(i) = sp.WinEyeFixY; win_eye_fix_r(i) = sp.WinEyeFixR;
        win_hnd_fix_x(i) = sp.WinHndFixX; win_hnd_fix_y(i) = sp.WinHndFixY; win_hnd_fix_r(i) = sp.WinHndFixR;
        win_eye_tar_x(i) = sp.WinEyeTarX; win_eye_tar_y(i) = sp.WinEyeTarY; win_eye_tar_r(i) = sp.WinEyeTarR;
        win_hnd_tar_x(i) = sp.WinHndTarX; win_hnd_tar_y(i) = sp.WinHndTarY; win_hnd_tar_r(i) = sp.WinHndTarR;
        win_eye_tar2_x(i) = sp.WinEyeTar2X; win_eye_tar2_y(i) = sp.WinEyeTar2Y; win_eye_tar2_r(i) = sp.WinEyeTar2R;
        win_hnd_tar2_x(i) = sp.WinHndTar2X; win_hnd_tar2_y(i) = sp.WinHndTar2Y; win_hnd_tar2_r(i) = sp.WinHndTar2R;
        win_hnd_cue_x(i) = sp.WinHndCueX; win_hnd_cue_y(i) = sp.WinHndCueY; win_hnd_cue_r(i) = sp.WinHndCueR;
        win_hnd_cue2_x(i) = sp.WinHndCue2X; win_hnd_cue2_y(i) = sp.WinHndCue2Y; win_hnd_cue2_r(i) = sp.WinHndCue2R;
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

    trials_tbl.AbortedState = aborted_state_col;
    trials_tbl.AbortedStateDuration = aborted_state_dur_col;
    trials_tbl.MpTaskType = mp_type_col;
    trials_tbl.TarX = tar_x_col;
    trials_tbl.TarY = tar_y_col;
    trials_tbl.EyeFixMeanX = eye_fix_mx; trials_tbl.EyeFixMeanY = eye_fix_my;
    trials_tbl.HndFixMeanX = hnd_fix_mx; trials_tbl.HndFixMeanY = hnd_fix_my;
    trials_tbl.EyeTarMeanX = eye_tar_mx; trials_tbl.EyeTarMeanY = eye_tar_my;
    trials_tbl.HndTarMeanX = hnd_tar_mx; trials_tbl.HndTarMeanY = hnd_tar_my;
    trials_tbl.EyeAbortPreX = eye_pre_x; trials_tbl.EyeAbortPreY = eye_pre_y;
    trials_tbl.HndAbortPreX = hnd_pre_x; trials_tbl.HndAbortPreY = hnd_pre_y;
    trials_tbl.EyeAbortPostX = eye_post_x; trials_tbl.EyeAbortPostY = eye_post_y;
    trials_tbl.HndAbortPostX = hnd_post_x; trials_tbl.HndAbortPostY = hnd_post_y;
    trials_tbl.WinEyeFixX = win_eye_fix_x; trials_tbl.WinEyeFixY = win_eye_fix_y; trials_tbl.WinEyeFixR = win_eye_fix_r;
    trials_tbl.WinHndFixX = win_hnd_fix_x; trials_tbl.WinHndFixY = win_hnd_fix_y; trials_tbl.WinHndFixR = win_hnd_fix_r;
    trials_tbl.WinEyeTarX = win_eye_tar_x; trials_tbl.WinEyeTarY = win_eye_tar_y; trials_tbl.WinEyeTarR = win_eye_tar_r;
    trials_tbl.WinHndTarX = win_hnd_tar_x; trials_tbl.WinHndTarY = win_hnd_tar_y; trials_tbl.WinHndTarR = win_hnd_tar_r;
    trials_tbl.WinEyeTar2X = win_eye_tar2_x; trials_tbl.WinEyeTar2Y = win_eye_tar2_y; trials_tbl.WinEyeTar2R = win_eye_tar2_r;
    trials_tbl.WinHndTar2X = win_hnd_tar2_x; trials_tbl.WinHndTar2Y = win_hnd_tar2_y; trials_tbl.WinHndTar2R = win_hnd_tar2_r;
    trials_tbl.WinHndCueX = win_hnd_cue_x; trials_tbl.WinHndCueY = win_hnd_cue_y; trials_tbl.WinHndCueR = win_hnd_cue_r;
    trials_tbl.WinHndCue2X = win_hnd_cue2_x; trials_tbl.WinHndCue2Y = win_hnd_cue2_y; trials_tbl.WinHndCue2R = win_hnd_cue2_r;

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

% Duration of DEL_PER and time from delay-end to first later TAR_HOL (NaN if absent).
function [delay_dur, target_acq_time] = get_delay_and_target_acq(trial, STATE)
    delay_dur = NaN;
    target_acq_time = NaN;
    if ~isfield(trial, 'states') || ~isfield(trial, 'states_onset')
        return;
    end
    states = trial.states(:);
    onsets = trial.states_onset(:);
    delay_idx = find(states == STATE.DEL_PER, 1, 'first');
    if isempty(delay_idx) || delay_idx >= numel(onsets)
        return;
    end
    delay_dur = onsets(delay_idx + 1) - onsets(delay_idx);
    idx_hold = find(states == STATE.TAR_HOL);
    idx_hold = idx_hold(idx_hold > delay_idx);
    if ~isempty(idx_hold) && idx_hold(1) <= numel(onsets)
        target_acq_time = onsets(idx_hold(1)) - onsets(delay_idx + 1);
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
        trial, success, STATE, delay_duration, reason, aborted_state)
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
    if nargin < 6
        aborted_state = get_trial_aborted_state(trial, STATE);
    end
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
    [~, t_del_end] = get_state_onset_and_next(trial, STATE.DEL_PER);
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

function plot_path = make_run_figure(trials_tbl, out_dir, run_base, title_str)
    if nargin < 4 || isempty(title_str)
        title_str = sprintf('Run: %s', run_base);
    end
    t_draw = tic;
    fig = figure('Visible', 'off', 'Position', [40 40 2000 1100]);
    tl = tiledlayout(fig, 3, 4, 'TileSpacing', 'compact', 'Padding', 'compact');
    fill_session_or_run_tiles(tl, trials_tbl, {}, false);
    sgtitle(tl, figure_main_title(title_str, trials_tbl), ...
        'FontWeight', 'bold', 'Interpreter', 'none');
    apply_figure_fonts(fig, 12, 13, 16);
    fprintf('  draw %5.1f s  run   %s\n', toc(t_draw), run_base);
    plot_path = fullfile(out_dir, [run_base '.pdf']);
    save_figure_pdf(fig, plot_path);
    close(fig);
end

function plot_path = make_session_figure(day_trials_tbl, run_trials_tbls, out_dir, base_name, title_str)
    t_draw = tic;
    fig = figure('Visible', 'off', 'Position', [40 40 2000 1100]);
    tl = tiledlayout(fig, 3, 4, 'TileSpacing', 'compact', 'Padding', 'compact');
    fill_session_or_run_tiles(tl, day_trials_tbl, run_trials_tbls, true);
    sgtitle(tl, figure_main_title(title_str, day_trials_tbl), ...
        'FontWeight', 'bold', 'Interpreter', 'none');
    apply_figure_fonts(fig, 12, 13, 16);
    fprintf('  draw %5.1f s  sess  %s\n', toc(t_draw), base_name);
    plot_path = fullfile(out_dir, [base_name '.pdf']);
    save_figure_pdf(fig, plot_path);
    close(fig);
end

function plot_path = make_error_figure(trials_tbl, run_trials_tbls, is_session, out_dir, base_name, title_str)
% Upper: abort-state % (hand x space) + abort times by state. Lower: endpoints for states in this task.
    t_draw = tic;
    fig = figure('Visible', 'off', 'Position', [40 40 2400 1150], ...
        'DefaultAxesFontSize', 14, 'DefaultTextFontSize', 14, ...
        'DefaultAxesFontWeight', 'bold');
    tl = tiledlayout(fig, 2, 5, 'TileSpacing', 'compact', 'Padding', 'compact');
    ST = get_task_state_dict().STATE;
    seq = abort_states_in_table(trials_tbl);

    nexttile(tl, 1, [1 2]);
    plot_aborted_state_hist(trials_tbl);

    nexttile(tl, 3, [1 3]);
    plot_abort_times_by_state(trials_tbl, run_trials_tbls, is_session);

    panels = {};
    if any(ismember([ST.FIX_ACQ, ST.FIX_HOL], seq))
        panels{end+1} = @() plot_endpoint_xy(trials_tbl, 'success_fix', 'Success FIX_HOL mean');
    end
    if any(ismember([ST.TAR_HOL, ST.TAR_HOL_INV], seq))
        panels{end+1} = @() plot_endpoint_xy(trials_tbl, 'success_tar', 'Success TAR_HOL mean');
    end
    if any(ismember([ST.FIX_ACQ, ST.FIX_HOL], seq))
        panels{end+1} = @() plot_endpoint_abort_pair( ...
            trials_tbl, [ST.FIX_ACQ ST.FIX_HOL], 'Abort FIX_ACQ/HOL');
    end
    cue_codes = intersect([ST.CUE_ON, ST.MEM_PER, ST.DEL_PER], seq, 'stable');
    if ~isempty(cue_codes)
        cue_title = abort_panel_title(cue_codes, 'Abort');
        panels{end+1} = @() plot_endpoint_abort_pair(trials_tbl, cue_codes, cue_title);
    end
    tar_codes = intersect([ST.TAR_ACQ, ST.TAR_HOL, ST.TAR_ACQ_INV, ST.TAR_HOL_INV], seq, 'stable');
    if ~isempty(tar_codes)
        tar_title = abort_panel_title(tar_codes, 'Abort');
        panels{end+1} = @() plot_endpoint_abort_pair(trials_tbl, tar_codes, tar_title);
    end
    for p = 1:5
        nexttile(tl, 5 + p);
        if p <= numel(panels)
            panels{p}();
        else
            axis off;
        end
    end

    sgtitle(tl, figure_main_title(title_str, trials_tbl), ...
        'FontWeight', 'bold', 'Interpreter', 'none', 'FontSize', 20);
    apply_figure_fonts(fig, 14, 15, 20);
    fprintf('  draw %5.1f s  err   %s\n', toc(t_draw), base_name);
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
    if table_has_cue_like_epoch(trials_tbl)
        plot_delay_percent_histogram(trials_tbl);
    else
        axis off;
        title(sprintf('No cue/delay (%s)', mp_task_info_str(trials_tbl)), ...
            'FontWeight', 'bold', 'Interpreter', 'none');
    end

    nexttile(tl, 11);
    plot_success_counts_at_targets(trials_tbl);

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
            'FontSize', 11, 'FontWeight', 'bold', 'Color', [0.1 0.1 0.1], ...
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
        '%d instructed trials, %d successful.  '], ...
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
    if ~table_has_cue_like_epoch(trials_tbl)
        text(0.5, 0.5, sprintf('No cue/delay (%s)', mp_task_info_str(trials_tbl)), ...
            'HorizontalAlignment', 'center', 'Interpreter', 'none');
        axis off;
        title('From cue', 'FontWeight', 'bold', 'Interpreter', 'none');
        return;
    end
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
        title(sprintf('Wait from cue  (abort %d) \n cue=%.2f del=%.2f+%.2f', ...
            n_abort, cue_hold, del_hold, del_var), ...
            'FontWeight', 'bold', 'Interpreter', 'none');
    else
        title(sprintf('Wait from cue  (succ %d [%.2f-%.2f], abort %d) \n cue=%.2f del=%.2f+%.2f', ...
            n_succ, min(success_vals), max(success_vals), n_abort, ...
            cue_hold, del_hold, del_var), ...
            'FontWeight', 'bold', 'Interpreter', 'none');
    end
    legend('Location', 'best');
    grid on;
    xlim([0, max_edge]);
end

function plot_success_counts_at_targets(trials_tbl)
% Same 2D deg axes as endpoint plots. Two bars stand on each target (x,y): instr | choice.
% Bar height is scaled to target spacing (not 1 trial = 1 deg) so rows do not overlap.
    if isempty(trials_tbl) || height(trials_tbl) == 0 || ...
            ~all(ismember({'TarX', 'TarY', 'Success', 'TaskType'}, ...
            trials_tbl.Properties.VariableNames))
        text(0.5, 0.5, 'No target positions', 'HorizontalAlignment', 'center');
        axis off;
        title('Successful targets', 'FontWeight', 'bold', 'Interpreter', 'none');
        return;
    end
    succ = trials_tbl.Success == 1 & isfinite(trials_tbl.TarX) & isfinite(trials_tbl.TarY);
    if ~any(succ)
        text(0.5, 0.5, 'No successful targets', 'HorizontalAlignment', 'center');
        axis off;
        title('Successful targets', 'FontWeight', 'bold', 'Interpreter', 'none');
        return;
    end
    q = 0.05;
    xy = round([trials_tbl.TarX(succ), trials_tbl.TarY(succ)] / q) * q;
    task = trials_tbl.TaskType(succ);
    [u_xy, ~, ic] = unique(xy, 'rows');
    n_pos = size(u_xy, 1);
    n_instr = accumarray(ic, double(task == "Instructed"), [n_pos, 1]);
    n_free = accumarray(ic, double(task == "Free"), [n_pos, 1]);
    n_max = max([n_instr; n_free; 1]);

    if n_pos == 1
        dmin = 6;
    else
        dist = hypot(u_xy(:, 1) - u_xy(:, 1)', u_xy(:, 2) - u_xy(:, 2)');
        dist(1:n_pos+1:end) = inf;
        dmin = min(dist, [], 'all');
        if ~(dmin > 0)
            dmin = 6;
        end
    end
    dy_up = u_xy(:, 2)' - u_xy(:, 2);
    dy_up(dy_up <= 0.05) = inf;
    min_gap = min(dy_up, [], 'all');
    if ~(min_gap < inf)
        min_gap = dmin;
    end
    % Tallest bar uses half the vertical gap to the next target row.
    deg_per_trial = (0.50 * min_gap) / n_max;
    w = min(1.2, max(0.35, dmin * 0.12));
    gap = w * 0.08;
    h_instr = n_instr * deg_per_trial;
    h_free = n_free * deg_per_trial;

    c = plot_colors();
    col_instr = (c.lh_instr + c.rh_instr) / 2;
    col_free = (c.lh_choice + c.rh_choice) / 2;

    hold on;
    plot_task_windows(trials_tbl);
    drew_instr = false;
    drew_free = false;
    for i = 1:n_pos
        tx = u_xy(i, 1);
        ty = u_xy(i, 2);
        if n_instr(i) > 0
            draw_count_bar2(tx - gap - w, ty, w, h_instr(i), col_instr, ~drew_instr, 'Instructed');
            drew_instr = true;
            text(tx - gap - w / 2, ty + h_instr(i), sprintf('%d', n_instr(i)), ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
                'FontWeight', 'bold', 'FontSize', 8, 'Interpreter', 'none', ...
                'Clipping', 'on');
        end
        if n_free(i) > 0
            draw_count_bar2(tx + gap, ty, w, h_free(i), col_free, ~drew_free, 'Choice');
            drew_free = true;
            text(tx + gap + w / 2, ty + h_free(i), sprintf('%d', n_free(i)), ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
                'FontWeight', 'bold', 'FontSize', 8, 'Interpreter', 'none', ...
                'Clipping', 'on');
        end
    end
    
    axis equal;
    lims = endpoint_axis_limits(trials_tbl, u_xy);
    set(gca, 'XLim', lims, 'YLim', lims, 'DataAspectRatio', [1 1 1], 'FontWeight', 'bold');
    xlabel('x (deg)', 'FontWeight', 'bold');
    ylabel('y (deg)', 'FontWeight', 'bold');
    title(sprintf('Suc. selection (n=%d; %.2f deg/trial)', ...
        sum(succ), deg_per_trial), 'FontWeight', 'bold', 'Interpreter', 'none');
    if drew_instr || drew_free
        legend('Location', 'best');
    end
    grid on;
end

function draw_count_bar2(x0, y0, w, h, col, show_leg, name)
    vis = 'off';
    if show_leg
        vis = 'on';
    end
    patch([x0, x0 + w, x0 + w, x0], [y0, y0, y0 + h, y0 + h], col, ...
        'EdgeColor', 'k', 'LineWidth', 0.8, ...
        'HandleVisibility', vis, 'DisplayName', name);
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

function plot_aborted_state_hist(trials_tbl)
    if isempty(trials_tbl) || height(trials_tbl) == 0 || ...
            ~ismember('AbortedState', trials_tbl.Properties.VariableNames)
        text(0.5, 0.5, 'No abort data', 'HorizontalAlignment', 'center');
        axis off;
        title('Aborted states', 'FontWeight', 'bold', 'Interpreter', 'none');
        return;
    end
    fail = trials_tbl.Success == 0 & ~isnan(trials_tbl.AbortedState);
    if ~any(fail)
        text(0.5, 0.5, 'No abort data', 'HorizontalAlignment', 'center');
        axis off;
        title('Aborted states', 'FontWeight', 'bold', 'Interpreter', 'none');
        return;
    end
    [keys, labels, colors, is_hollow] = abort_hist_series_config();
    codes = abort_states_in_table(trials_tbl);
    n_fail = sum(fail);
    n_s = numel(codes);
    n_g = numel(keys);
    counts = zeros(n_s, n_g);
    st = trials_tbl.AbortedState(fail);
    reasons = trials_tbl.reason_of_abort(fail);
    hands = trials_tbl.Hand(fail);
    targs = trials_tbl.Target(fail);
    for i = 1:n_fail
        si = find(codes == st(i), 1, 'first');
        gi = abort_hist_series_index(st(i), reasons(i), hands(i), targs(i), keys);
        if ~isempty(si) && gi > 0
            counts(si, gi) = counts(si, gi) + 1;
        end
    end
    pct = counts / n_fail * 100;
    x = 1:n_s;
    x_bar = x;
    pct_bar = pct;
    if size(pct_bar, 1) == 1
        pct_bar = [pct_bar; nan(1, n_g)];
        x_bar = [x, x(end) + 1];
    end
    bh = bar(x_bar, pct_bar, 0.88, 'grouped');
    hold on;
    for g = 1:n_g
        bh(g).DisplayName = labels{g};
        bh(g).HandleVisibility = 'on';
        bh(g).LineWidth = 1.4;
        if is_hollow(g)
            bh(g).FaceColor = [1 1 1];
            bh(g).EdgeColor = colors(g, :);
        else
            bh(g).FaceColor = colors(g, :);
            bh(g).EdgeColor = 'k';
        end
    end
    xt = cell(1, n_s);
    for i = 1:n_s
        xt{i} = sprintf('%s (%d)', state_code_to_name(codes(i)), sum(counts(i, :)));
    end
    set(gca, 'XTick', x, 'XTickLabel', xt, 'FontWeight', 'bold', ...
        'TickLabelInterpreter', 'none');
    xtickangle(20);
    ylabel('% of failed trials', 'FontWeight', 'bold');
    title(sprintf('Aborted states  (n=%d failed)', n_fail), ...
        'FontWeight', 'bold', 'Interpreter', 'none');
    legend(bh, labels, 'Location', 'best', 'NumColumns', 2);
    grid on;
    xlim([0.5, n_s + 0.5]);
    ymax = max(pct(:));
    if ~(ymax > 0)
        ymax = 1;
    end
    ylim([0, ymax * 1.18]);
    if n_g > 1
        halfw = abs(bh(2).XEndPoints(1) - bh(1).XEndPoints(1)) * 0.38;
    else
        halfw = 0.12;
    end
    y0 = 0.012 * ymax;
    for g = 1:n_g
        xe = bh(g).XEndPoints;
        xe = xe(1:min(n_s, numel(xe)));
        for si = 1:numel(xe)
            if counts(si, g) > 0
                continue;
            end
            plot(xe(si) + [-halfw, halfw], [y0, y0], '-', ...
                'Color', colors(g, :), 'LineWidth', 2.0, ...
                'HandleVisibility', 'off');
        end
    end
end

function [keys, labels, colors, is_hollow] = abort_hist_series_config()
% Hollow (white + colored edge) = no space yet. Filled = space L/R.
    c = plot_colors();
    eye0 = [1.00, 0.50, 0.10];
    eyeL = [0.80, 0.30, 0.00];
    eyeR = [1.00, 0.72, 0.28];
    keys = {'eye', 'eye_L', 'eye_R', 'lh', 'rh', 'lh_L', 'lh_R', 'rh_L', 'rh_R'};
    labels = {'Eye', 'Eye L', 'Eye R', 'LH', 'RH', 'LH L', 'LH R', 'RH L', 'RH R'};
    colors = [eye0; eyeL; eyeR; c.lh; c.rh; c.lh_instr; c.lh_choice; c.rh_instr; c.rh_choice];
    is_hollow = [true, false, false, true, true, false, false, false, false];
end

function gi = abort_hist_series_index(state, reason, hand, target, keys)
    key = abort_hist_series_key(state, reason, hand, target);
    gi = find(strcmp(keys, key), 1, 'first');
    if isempty(gi)
        gi = 0;
    end
end

function key = abort_hist_series_key(state, reason, hand, target)
    r = lower(char(string(reason)));
    is_eye = contains(r, 'abort_eye');
    use_space = abort_state_has_space(state) && (target == "Left" || target == "Right");
    if is_eye
        if use_space && target == "Left"
            key = 'eye_L';
        elseif use_space && target == "Right"
            key = 'eye_R';
        else
            key = 'eye';
        end
        return;
    end
    if use_space && hand == "Left" && target == "Left"
        key = 'lh_L';
    elseif use_space && hand == "Left" && target == "Right"
        key = 'lh_R';
    elseif use_space && hand == "Right" && target == "Left"
        key = 'rh_L';
    elseif use_space && hand == "Right" && target == "Right"
        key = 'rh_R';
    elseif hand == "Right"
        key = 'rh';
    else
        key = 'lh';
    end
end

function tf = abort_state_has_space(code)
% Cue/target on: CUE_ON, DEL_PER, MEM_PER, TAR_*. Not FIX_*.
    ST = get_task_state_dict().STATE;
    tf = ismember(double(code), [ST.CUE_ON, ST.MEM_PER, ST.DEL_PER, ...
        ST.TAR_ACQ, ST.TAR_HOL, ST.TAR_ACQ_INV, ST.TAR_HOL_INV]);
end

function plot_abort_times_by_state(trials_tbl, run_trials_tbls, is_session)
    codes = abort_states_in_table(trials_tbl);
    if isempty(codes)
        text(0.5, 0.5, 'No abort times', 'HorizontalAlignment', 'center');
        axis off;
        title('Abort time by state', 'FontWeight', 'bold', 'Interpreter', 'none');
        return;
    end
    [means, sems, ns, trial_cells] = abort_time_by_state_stats(trials_tbl, codes);
    x = 1:numel(codes);
    col = [0.45 0.45 0.45];
    colors = repmat(col, numel(codes), 1);
    bar(x, means, 0.7, 'FaceColor', col, 'EdgeColor', 'k');
    hold on;
    errorbar(x, means, sems, 'k.', 'LineWidth', 1.0, 'CapSize', 6);
    if is_session
        overlay_run_means(x, run_trials_tbls, @(tbl) abort_time_by_state_means(tbl, codes), colors);
    else
        overlay_trial_dots(x, trial_cells, colors);
    end
    uistack(findall(gca, 'Type', 'Scatter'), 'top');
    labels = cell(size(codes));
    for i = 1:numel(codes)
        labels{i} = state_code_to_name(codes(i));
    end
    set(gca, 'XTick', x, 'XTickLabel', labels, 'FontWeight', 'bold', ...
        'TickLabelInterpreter', 'none');
    xtickangle(25);
    ylabel('Aborted-state duration (s)', 'FontWeight', 'bold');
    title(sprintf('Abort time by state  (n=%d)', sum(ns)), ...
        'FontWeight', 'bold', 'Interpreter', 'none');
    grid on;
    label_bar_n(x, ns, 0);
end

function means = abort_time_by_state_means(tbl, codes)
    [means, ~, ~, ~] = abort_time_by_state_stats(tbl, codes);
end

function codes = abort_states_in_table(tbl)
% Mid-sequence states for the MonkeyPsych type(s) in this table (no unused epochs).
    codes = mp_task_mid_states(mp_task_types_in_table(tbl));
end

function types = mp_task_types_in_table(tbl)
    types = [];
    if ~isempty(tbl) && height(tbl) > 0 && ismember('MpTaskType', tbl.Properties.VariableNames)
        v = tbl.MpTaskType(~isnan(tbl.MpTaskType));
        types = unique(v(:)');
    end
    if isempty(types)
        types = 4;
    end
end

function codes = mp_task_mid_states(mp_types)
    dict = get_task_state_dict();
    TASK = dict.TASK;
    codes = [];
    mp_types = unique(mp_types(~isnan(mp_types)));
    if isempty(mp_types)
        mp_types = 4;
    end
    task_ids = [TASK.type];
    for t = mp_types(:)'
        hit = find(abs(task_ids - t) < 1e-6, 1, 'first');
        if isempty(hit)
            continue;
        end
        codes = [codes, TASK(hit).state_codes]; %#ok<AGROW>
    end
    if isempty(codes)
        ST = dict.STATE;
        codes = [ST.FIX_ACQ, ST.FIX_HOL, ST.CUE_ON, ST.DEL_PER, ST.TAR_ACQ, ST.TAR_HOL];
    end
    codes = sort_abort_states_chrono(unique(codes, 'stable'));
end

function tf = table_has_cue_like_epoch(tbl)
    ST = get_task_state_dict().STATE;
    tf = any(ismember(abort_states_in_table(tbl), [ST.CUE_ON, ST.MEM_PER, ST.DEL_PER]));
end

function s = figure_main_title(base, trials_tbl)
    info = mp_task_info_str(trials_tbl);
    if strlength(string(info)) == 0
        s = char(base);
    else
        s = sprintf('%s  [%s]', char(base), info);
    end
end

function s = mp_task_info_str(tbl)
    dict = get_task_state_dict();
    TASK = dict.TASK;
    types = mp_task_types_in_table(tbl);
    task_ids = [TASK.type];
    parts = cell(numel(types), 1);
    for i = 1:numel(types)
        hit = find(abs(task_ids - types(i)) < 1e-6, 1, 'first');
        if isempty(hit)
            parts{i} = sprintf('type %g', types(i));
        else
            parts{i} = sprintf('type %g %s', types(i), TASK(hit).info);
        end
    end
    s = strjoin(parts, '; ');
end

function title_str = abort_panel_title(codes, prefix)
    names = cell(numel(codes), 1);
    for i = 1:numel(codes)
        names{i} = state_code_to_name(codes(i));
    end
    title_str = sprintf('%s %s', prefix, strjoin(names, '/'));
end

function codes = sort_abort_states_chrono(codes)
% Task order: FIX -> CUE/DEL -> TAR (numeric codes put TAR before CUE).
    codes = codes(:)';
    if isempty(codes)
        return;
    end
    ST = get_task_state_dict().STATE;
    preferred = [ST.FIX_ACQ, ST.FIX_HOL, ST.CUE_ON, ST.DEL_PER, ST.MEM_PER, ...
        ST.TAR_ACQ, ST.TAR_HOL, ST.TAR_ACQ_INV, ST.TAR_HOL_INV, ST.INI_TRI, ST.ABORT];
    loc = zeros(size(codes));
    for i = 1:numel(codes)
        k = find(preferred == codes(i), 1, 'first');
        if isempty(k)
            loc(i) = 1000 + codes(i);
        else
            loc(i) = k;
        end
    end
    [~, ord] = sort(loc);
    codes = codes(ord);
end

function [means, sems, ns, trial_cells] = abort_time_by_state_stats(tbl, codes)
    n = numel(codes);
    means = nan(1, n);
    sems = nan(1, n);
    ns = zeros(1, n);
    trial_cells = cell(1, n);
    if n == 0 || isempty(tbl) || height(tbl) == 0 || ...
            ~ismember('AbortedStateDuration', tbl.Properties.VariableNames)
        return;
    end
    for i = 1:n
        idx = tbl.Success == 0 & tbl.AbortedState == codes(i) & ...
            ~isnan(tbl.AbortedStateDuration);
        vals = tbl.AbortedStateDuration(idx);
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

function plot_endpoint_xy(trials_tbl, mode, title_str)
    eye_col = [1.00, 0.50, 0.10];
    if isempty(trials_tbl) || height(trials_tbl) == 0
        text(0.5, 0.5, 'No endpoint data', 'HorizontalAlignment', 'center');
        axis off;
        title(title_str, 'FontWeight', 'bold', 'Interpreter', 'none');
        return;
    end
    switch mode
        case 'success_fix'
            keep = trials_tbl.Success == 1;
            ex = trials_tbl.EyeFixMeanX; ey = trials_tbl.EyeFixMeanY;
            hx = trials_tbl.HndFixMeanX; hy = trials_tbl.HndFixMeanY;
        case 'success_tar'
            keep = trials_tbl.Success == 1;
            ex = trials_tbl.EyeTarMeanX; ey = trials_tbl.EyeTarMeanY;
            hx = trials_tbl.HndTarMeanX; hy = trials_tbl.HndTarMeanY;
        otherwise
            keep = true(height(trials_tbl), 1);
            ex = nan(height(trials_tbl), 1); ey = ex; hx = ex; hy = ex;
    end
    n_eye = sum(keep & ~isnan(ex) & ~isnan(ey));
    n_hnd = sum(keep & ~isnan(hx) & ~isnan(hy));
    if n_eye == 0 && n_hnd == 0
        text(0.5, 0.5, 'No endpoint data', 'HorizontalAlignment', 'center');
        axis off;
        title(title_str, 'FontWeight', 'bold', 'Interpreter', 'none');
        return;
    end

    hold on;
    plot_task_windows(trials_tbl);

    idx_e = keep & ~isnan(ex) & ~isnan(ey);
    scatter(ex(idx_e), ey(idx_e), 12, 'o', ...
        'MarkerFaceColor', eye_col, 'MarkerEdgeColor', 'none', ...
        'MarkerFaceAlpha', 0.65, 'DisplayName', 'Eye');

    extra_xy = [ex(idx_e), ey(idx_e)];
    for hand = ["Left", "Right"]
        idx_h = keep & trials_tbl.Hand == hand & ~isnan(hx) & ~isnan(hy);
        if ~any(idx_h)
            continue;
        end
        col = color_hand_task(hand, "");
        scatter(hx(idx_h), hy(idx_h), 14, 'o', ...
            'MarkerFaceColor', col, 'MarkerEdgeColor', 'none', ...
            'MarkerFaceAlpha', 0.65, 'DisplayName', char(hand + " hand"));
        extra_xy = [extra_xy; hx(idx_h), hy(idx_h)]; %#ok<AGROW>
    end

    axis equal;
    lims = endpoint_axis_limits(trials_tbl, extra_xy);
    set(gca, 'XLim', lims, 'YLim', lims, 'DataAspectRatio', [1 1 1], 'FontWeight', 'bold');
    xlabel('x', 'FontWeight', 'bold');
    ylabel('y', 'FontWeight', 'bold');
    title(sprintf('%s  (eye %d, hnd %d)', title_str, n_eye, n_hnd), ...
        'FontWeight', 'bold', 'Interpreter', 'none');
    legend('Location', 'best');
    grid on;
end

function plot_endpoint_abort_pair(trials_tbl, state_codes, title_str)
% Pre and post abort samples on one axes, connected. Windows from all trials.
    eye_col = [1.00, 0.50, 0.10];
    if isempty(trials_tbl) || height(trials_tbl) == 0
        text(0.5, 0.5, 'No abort data', 'HorizontalAlignment', 'center');
        axis off;
        title(title_str, 'FontWeight', 'bold', 'Interpreter', 'none');
        return;
    end
    keep = trials_tbl.Success == 0 & ismember(trials_tbl.AbortedState, state_codes);
    n_keep = sum(keep);
    hold on;
    plot_task_windows(trials_tbl);

    extra_xy = zeros(0, 2);
    extra_xy = plot_abort_effector_pairs( ...
        trials_tbl, keep, 'EyeAbortPreX', 'EyeAbortPreY', 'EyeAbortPostX', 'EyeAbortPostY', ...
        [], eye_col, 'Eye', extra_xy);
    extra_xy = plot_abort_effector_pairs( ...
        trials_tbl, keep, 'HndAbortPreX', 'HndAbortPreY', 'HndAbortPostX', 'HndAbortPostY', ...
        "Left", color_hand_task("Left", ""), 'Left hand', extra_xy);
    extra_xy = plot_abort_effector_pairs( ...
        trials_tbl, keep, 'HndAbortPreX', 'HndAbortPreY', 'HndAbortPostX', 'HndAbortPostY', ...
        "Right", color_hand_task("Right", ""), 'Right hand', extra_xy);

    axis equal;
    lims = endpoint_axis_limits(trials_tbl, extra_xy);
    set(gca, 'XLim', lims, 'YLim', lims, 'DataAspectRatio', [1 1 1], 'FontWeight', 'bold');
    xlabel('x', 'FontWeight', 'bold');
    ylabel('y', 'FontWeight', 'bold');
    title(sprintf('%s  n=%d', title_str, n_keep), ...
        'FontWeight', 'bold', 'Interpreter', 'none');
    legend('Location', 'best');
    grid on;
end

function extra_xy = plot_abort_effector_pairs(tbl, keep, xpre, ypre, xpost, ypost, hand, col, name, extra_xy)
    idx = keep;
    if ~isempty(hand)
        idx = idx & tbl.Hand == hand;
    end
    xp = tbl.(xpre); yp = tbl.(ypre);
    xo = tbl.(xpost); yo = tbl.(ypost);
    has_pre = idx & ~isnan(xp) & ~isnan(yp);
    has_post = idx & ~isnan(xo) & ~isnan(yo);
    both = has_pre & has_post;
    if any(both)
        n = sum(both);
        xx = [xp(both), xo(both), nan(n, 1)]';
        yy = [yp(both), yo(both), nan(n, 1)]';
        plot(xx(:), yy(:), '-', 'Color', [col, 0.40], 'LineWidth', 0.5, ...
            'HandleVisibility', 'off');
    end
    shown = false;
    if any(has_pre)
        scatter(xp(has_pre), yp(has_pre), 16, 'o', ...
            'MarkerFaceColor', col, 'MarkerEdgeColor', 'none', ...
            'MarkerFaceAlpha', 0.75, 'DisplayName', name);
        extra_xy = [extra_xy; xp(has_pre), yp(has_pre)];
        shown = true;
    end
    if any(has_post)
        vis = 'off';
        dname = name;
        if ~shown
            vis = 'on';
        end
        scatter(xo(has_post), yo(has_post), 16, 'o', ...
            'MarkerFaceColor', 'none', 'MarkerEdgeColor', col, ...
            'LineWidth', 0.8, 'HandleVisibility', vis, 'DisplayName', dname);
        extra_xy = [extra_xy; xo(has_post), yo(has_post)];
    end
end

function plot_task_windows(trials_tbl)
% Eye windows orange; hand fix/tar/cue dark yellow (not LH/RH blue/green).
    eye_face = [1.00 0.70 0.35];
    eye_edge = [0.85 0.40 0.05];
    hnd_face = [0.85 0.70 0.12];
    hnd_edge = [0.55 0.40 0.02];
    plot_unique_window_set(trials_tbl, { ...
        {'WinEyeFixX', 'WinEyeFixY', 'WinEyeFixR'}, ...
        {'WinEyeTarX', 'WinEyeTarY', 'WinEyeTarR'}, ...
        {'WinEyeTar2X', 'WinEyeTar2Y', 'WinEyeTar2R'}}, eye_face, eye_edge);
    plot_unique_window_set(trials_tbl, { ...
        {'WinHndFixX', 'WinHndFixY', 'WinHndFixR'}, ...
        {'WinHndTarX', 'WinHndTarY', 'WinHndTarR'}, ...
        {'WinHndTar2X', 'WinHndTar2Y', 'WinHndTar2R'}, ...
        {'WinHndCueX', 'WinHndCueY', 'WinHndCueR'}, ...
        {'WinHndCue2X', 'WinHndCue2Y', 'WinHndCue2R'}}, hnd_face, hnd_edge);
end

function plot_unique_window_set(tbl, triples, face, edge)
    xy = zeros(0, 3);
    for i = 1:numel(triples)
        f = triples{i};
        if ~all(ismember(f, tbl.Properties.VariableNames))
            continue;
        end
        block = [tbl.(f{1}), tbl.(f{2}), tbl.(f{3})];
        block = block(all(isfinite(block), 2), :);
        xy = [xy; block]; %#ok<AGROW>
    end
    if isempty(xy)
        return;
    end
    xy = unique(round(xy, 4), 'rows');
    th = linspace(0, 2*pi, 80);
    ct = cos(th); st = sin(th);
    for i = 1:size(xy, 1)
        x = xy(i, 1) + xy(i, 3) * ct;
        y = xy(i, 2) + xy(i, 3) * st;
        patch(x, y, face, 'FaceAlpha', 0.10, 'EdgeColor', edge, ...
            'LineWidth', 1.0, 'HandleVisibility', 'off');
        plot(xy(i, 1), xy(i, 2), '+', 'Color', edge, 'MarkerSize', 8, ...
            'LineWidth', 1.2, 'HandleVisibility', 'off');
    end
end

function lims = endpoint_axis_limits(tbl, extra_xy)
% Origin-centered square covering window extents (center ± radius) and points.
    pad = 2;
    m = 8;
    specs = { ...
        'WinEyeFixX', 'WinEyeFixY', 'WinEyeFixR'; ...
        'WinHndFixX', 'WinHndFixY', 'WinHndFixR'; ...
        'WinEyeTarX', 'WinEyeTarY', 'WinEyeTarR'; ...
        'WinEyeTar2X', 'WinEyeTar2Y', 'WinEyeTar2R'; ...
        'WinHndTarX', 'WinHndTarY', 'WinHndTarR'; ...
        'WinHndTar2X', 'WinHndTar2Y', 'WinHndTar2R'; ...
        'WinHndCueX', 'WinHndCueY', 'WinHndCueR'; ...
        'WinHndCue2X', 'WinHndCue2Y', 'WinHndCue2R'};
    for i = 1:size(specs, 1)
        xf = specs{i, 1}; yf = specs{i, 2}; rf = specs{i, 3};
        if ~all(ismember({xf, yf, rf}, tbl.Properties.VariableNames))
            continue;
        end
        xyz = [tbl.(xf), tbl.(yf), tbl.(rf)];
        xyz = xyz(all(isfinite(xyz), 2), :);
        if isempty(xyz)
            continue;
        end
        m = max([m; abs(xyz(:, 1)) + xyz(:, 3); abs(xyz(:, 2)) + xyz(:, 3)]);
    end
    if nargin >= 2 && ~isempty(extra_xy)
        extra_xy = extra_xy(all(isfinite(extra_xy), 2), :);
        if ~isempty(extra_xy)
            m = max([m; abs(extra_xy(:))]);
        end
    end
    lims = [-(m + pad), m + pad];
end

function dict = get_task_state_dict()
% STATE / STATE_NAME from ma1_task_state_dictionary.m (local fns cannot see caller workspace).
    persistent CACHE
    if isempty(CACHE)
        run(fullfile(fileparts(mfilename('fullpath')), 'ma1_task_state_dictionary.m'));
        CACHE = struct('STATE', STATE, 'STATE_NAME', STATE_NAME, 'TASK', TASK);
    end
    dict = CACHE;
end

function name = state_code_to_name(code)
    map = get_task_state_dict().STATE_NAME;
    code = double(code);
    if isKey(map, code)
        name = map(code);
    else
        name = sprintf('S%g', code);
    end
end

function apply_figure_fonts(fig, ax_sz, title_sz, sg_sz)
    if isempty(fig) || ~ishghandle(fig)
        return;
    end
    axs = findall(fig, 'Type', 'axes');
    for i = 1:numel(axs)
        ax = axs(i);
        set(ax, 'FontSize', ax_sz, 'FontWeight', 'bold');
        if ~isempty(ax.Title) && isprop(ax.Title, 'FontSize')
            ax.Title.FontSize = title_sz;
            ax.Title.FontWeight = 'bold';
        end
        if ~isempty(ax.XLabel)
            ax.XLabel.FontSize = ax_sz;
            ax.XLabel.FontWeight = 'bold';
        end
        if ~isempty(ax.YLabel)
            ax.YLabel.FontSize = ax_sz;
            ax.YLabel.FontWeight = 'bold';
        end
    end
    legs = findall(fig, 'Type', 'legend');
    if ~isempty(legs)
        set(legs, 'FontSize', max(ax_sz - 1, 10), 'FontWeight', 'bold');
    end
    tls = findall(fig, 'Type', 'tiledlayout');
    for i = 1:numel(tls)
        tl = tls(i);
        if isprop(tl, 'Title') && ~isempty(tl.Title)
            if isprop(tl.Title, 'FontSize')
                tl.Title.FontSize = sg_sz;
            end
            tl.Title.FontWeight = 'bold';
            if isprop(tl.Title, 'Interpreter')
                tl.Title.Interpreter = 'none';
            end
        end
        if isprop(tl, 'Subtitle') && ~isempty(tl.Subtitle) && isprop(tl.Subtitle, 'Interpreter')
            tl.Subtitle.Interpreter = 'none';
        end
    end
end

function save_figure_pdf(fig, plot_path)
% Write PDF; if destination is locked (Acrobat/etc), write alongside then error clearly.
    tmp_path = [plot_path '.tmp.pdf'];
    t_pdf = tic;
    used = 'exportgraphics-vector';
    try
        exportgraphics(fig, tmp_path, 'ContentType', 'vector');
    catch ME
        try
            print(fig, tmp_path, '-dpdf', '-vector');
            used = 'print-vector';
        catch ME2
            if isfile(tmp_path), delete(tmp_path); end
            error('Failed to save PDF %s\nexportgraphics: %s\nprint: %s', ...
                plot_path, ME.message, ME2.message);
        end
    end
    fprintf('  PDF %5.1f s  [%s]  %s\n', toc(t_pdf), used, plot_path);
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

    n_lines = 3 + max(n_bad, 1);
    lines = cell(n_lines, 1);
    k = 0;
    k = k + 1; lines{k} = sprintf('RT/MT validity report  [%s]  run_base=%s', run_label, char(run_base));
    if ismember('File', trials_tbl.Properties.VariableNames) && height(trials_tbl) > 0
        k = k + 1; lines{k} = sprintf('File: %s', char(string(trials_tbl.File(1))));
    end
    k = k + 1; lines{k} = sprintf('Successful trials: %d', n_succ);

    if n_bad == 0
        k = k + 1; lines{k} = sprintf('Timing OK: all %d successful trials have valid RT/MT', n_succ);
    else
        k = k + 1; lines{k} = sprintf( ...
            'Timing issues: %d / %d successful trials missing valid RT/MT', ...
            n_bad, n_succ);
        idx = find(bad);
        for b = 1:numel(idx)
            i = idx(b);
            miss = shorts(isnan([ ...
                trials_tbl.RTFixToSensorRelease(i), trials_tbl.MTSensorToFixHold(i), ...
                trials_tbl.RTGoToMovement(i), trials_tbl.MTMovementToTarget(i)]));
            hand = char(trials_tbl.Hand(i));
            task = char(trials_tbl.TaskType(i));
            if strlength(string(hand)) == 0, hand = '?'; end
            if strlength(string(task)) == 0, task = '?'; end
            k = k + 1; lines{k} = sprintf('  trial %d  hand=%s  task=%s  missing: %s', ...
                trials_tbl.Trial(i), hand, task, strjoin(miss, ', '));
        end
    end
    lines = lines(1:k);

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
    cleaner = onCleanup(@() fclose(fid));
    for i = 1:numel(lines)
        fprintf(fid, '%s\n', lines{i});
    end
    fprintf('  Wrote %s\n', report_path);
end

function [rt_fix_sensor, mt_sensor_fix, rt_go_move, mt_move_target] = get_trial_timing_metrics(trial, STATE, t_pre)
% Four latencies for one successful trial (NaN if a stage cannot be detected).
%
% FIXATION epoch:
%   RTFixToSensorRelease = FIX_ACQ onset -> home-sensor release
%   MTSensorToFixHold    = sensor release -> FIX_HOL onset
% REACH epoch:
%   RTGoToMovement       = TAR_ACQ (Go) -> hand leaves screen fixation
%   MTMovementToTarget   = speed onset near fixation (else detach) -> TAR_HOL
%
% Shared event times + aligned sample clock are reused (no 2nd/3rd align).
    if nargin < 3
        t_pre = [];
    end
    cfg = get_timing_detection_config();
    cache = struct();
    cache.t_fix_acq = get_fix_acq_onset(trial, STATE);
    cache.t_fix_hol = get_state_event_onset(trial, STATE.FIX_HOL);
    cache.t_go = get_go_cue_onset(trial, STATE);
    cache.t_release = get_sensor_release_time(trial, cache.t_fix_acq, cache.t_fix_hol, STATE, t_pre);
    cache.t_pre = t_pre;

    rt_fix_sensor = get_rt_fix_to_sensor_release_cached(cfg, cache);
    mt_sensor_fix = get_mt_sensor_to_fix_hold_cached(cfg, cache);
    [rt_go_move, mt_move_target] = get_reach_epoch_timing_cached(trial, STATE, cache, cfg);
end

function rt_fix = get_rt_fix_to_sensor_release_cached(cfg, cache)
    rt_fix = NaN;
    if ~isnan(cache.t_fix_acq) && ~isnan(cache.t_release)
        rt_fix = sanitize_latency(cache.t_release - cache.t_fix_acq, cfg.min_rt_fix, cfg.max_rt_fix);
    end
end

function mt_fix = get_mt_sensor_to_fix_hold_cached(cfg, cache)
    mt_fix = NaN;
    if ~isnan(cache.t_release) && ~isnan(cache.t_fix_hol)
        mt_fix = sanitize_latency(cache.t_fix_hol - cache.t_release, cfg.min_mt_fix, cfg.max_mt_fix);
    end
end

function [rt_go, mt_target] = get_reach_epoch_timing_cached(trial, STATE, cache, cfg)
    rt_go = NaN;
    mt_target = NaN;
    if nargin < 4
        cfg = get_timing_detection_config();
    end
    if isnan(cache.t_go)
        return;
    end
    if isfield(cache, 't_pre')
        t_pre = cache.t_pre;
    else
        t_pre = [];
    end
    [t, x, y, state] = get_aligned_hand_kinematics(trial, STATE, t_pre);
    if numel(t) < 3
        return;
    end
    t_tar_hol = get_state_event_onset(trial, STATE.TAR_HOL);
    t_detach = detect_fixation_detach_after_go(t, x, y, cache.t_go, cfg, t_tar_hol);
    if isnan(t_detach)
        return;
    end
    rt_go = sanitize_latency(t_detach - cache.t_go, cfg.min_rt_go, cfg.max_rt_go);
    if isnan(rt_go)
        return;
    end
    t_mt_start = detect_speed_onset_near_fixation(t, x, y, cache.t_go, cfg, t_tar_hol);
    if isnan(t_mt_start)
        t_mt_start = t_detach;
    end
    mt_target = get_mt_movement_to_target(t, x, y, state, t_mt_start, t_tar_hol, cfg, STATE);
end

function mt_target = get_mt_movement_to_target(t, x, y, state, t_move_start, t_tar_hol, cfg, STATE)
    mt_target = NaN;
    if isnan(t_move_start)
        return;
    end
    t_target = get_target_hold_onset_time(t, x, y, state, t_move_start, t_tar_hol, cfg, STATE);
    if isnan(t_target)
        return;
    end
    mt_target = sanitize_latency(t_target - t_move_start, cfg.min_mt_target, cfg.max_mt_target);
end

function cfg = get_timing_detection_config()
    persistent CFG
    if isempty(CFG)
        CFG.min_rt_fix = 0.05;
        CFG.max_rt_fix = 5.0;
        CFG.min_mt_fix = 0.01;
        CFG.max_mt_fix = 5.0;
        CFG.min_rt_go = 0.05;
        CFG.max_rt_go = 2.0;
        CFG.pre_go_baseline_win = 0.10;
        CFG.fix_exit_radius = 1.2;
        CFG.move_onset_speed_abs = 400;
        CFG.move_onset_speed_margin = 150;
        CFG.move_onset_max_disp = 2.0;
        CFG.min_mt_target = 0.10;
        CFG.max_mt_target = 2.0;
        CFG.target_hold_window = 0.05;
        CFG.target_acq_radius = 5;
        CFG.target_sustain_samples = 3;
    end
    cfg = CFG;
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
    [t_on, ~] = get_state_onset_and_next(trial, state_code);
end

function [t_on, t_next] = get_state_onset_and_next(trial, state_code)
    t_on = NaN;
    t_next = NaN;
    if ~isfield(trial, 'states') || ~isfield(trial, 'states_onset')
        return;
    end
    states = trial.states(:);
    onsets = trial.states_onset(:);
    idx = find(states == state_code, 1, 'first');
    if isempty(idx) || idx > numel(onsets)
        return;
    end
    t_on = onsets(idx);
    if idx < numel(onsets)
        t_next = onsets(idx + 1);
    end
end

function t_release = get_sensor_release_time(trial, t_after, t_before, STATE, t_pre)
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
    if nargin >= 5 && ~isempty(t_pre)
        t = t_pre(:);
    else
        t = trial.tSample_from_time_start(:);
    end
    if numel(sen) < 2 || numel(t) < 2
        return;
    end
    n = min(numel(sen), numel(t));
    sen = sen(1:n);
    t = t(1:n);
    if nargin < 5 || isempty(t_pre)
        t = align_tsample_to_state_time(trial, t, STATE);
    end
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

function t = get_aligned_sample_time(trial, STATE)
    t = [];
    if ~isfield(trial, 'tSample_from_time_start') || isempty(trial.tSample_from_time_start)
        return;
    end
    t = align_tsample_to_state_time(trial, trial.tSample_from_time_start(:), STATE);
end

function [t, x, y, state] = get_aligned_hand_kinematics(trial, STATE, t_pre)
    if nargin < 3
        t_pre = [];
    end
    [t, x, y, state] = get_aligned_stream_kinematics(trial, STATE, 'x_hnd', 'y_hnd', false, t_pre);
end

function [t, x, y, state] = get_aligned_stream_kinematics(trial, STATE, xfield, yfield, keep_nan, t_pre)
    t = [];
    x = [];
    y = [];
    state = [];
    if nargin < 5
        keep_nan = false;
    end
    if nargin < 6
        t_pre = [];
    end
    if ~isfield(trial, 'tSample_from_time_start') || ~isfield(trial, xfield) || ~isfield(trial, yfield)
        return;
    end
    if ~isempty(t_pre)
        t = t_pre(:);
    else
        t = trial.tSample_from_time_start(:);
    end
    x = trial.(xfield)(:);
    y = trial.(yfield)(:);
    if isfield(trial, 'state') && ~isempty(trial.state)
        state = trial.state(:);
    end
    n = min([numel(t), numel(x), numel(y)]);
    if ~isempty(state)
        n = min(n, numel(state));
    end
    if n < 1
        t = []; x = []; y = []; state = [];
        return;
    end
    t = t(1:n);
    if isempty(t_pre)
        t = align_tsample_to_state_time(trial, t, STATE);
    end
    x = x(1:n);
    y = y(1:n);
    if ~isempty(state)
        state = state(1:n);
    end
    if keep_nan
        valid = ~isnan(t);
    else
        valid = ~isnan(x) & ~isnan(y) & ~isnan(t);
    end
    t = t(valid);
    x = x(valid);
    y = y(valid);
    if ~isempty(state)
        state = state(valid);
    end
end

function sp = get_trial_spatial_metrics(trial, STATE, t_pre, aborted_state, abr_dur)
% Windows + hold means + abort pre/post samples (eye and hand).
    if nargin < 3
        t_pre = [];
    end
    if nargin < 4
        aborted_state = [];
    end
    if nargin < 5
        abr_dur = [];
    end
    sp = struct( ...
        'AbortedState', NaN, 'AbortedStateDuration', NaN, ...
        'EyeFixMeanX', NaN, 'EyeFixMeanY', NaN, 'HndFixMeanX', NaN, 'HndFixMeanY', NaN, ...
        'EyeTarMeanX', NaN, 'EyeTarMeanY', NaN, 'HndTarMeanX', NaN, 'HndTarMeanY', NaN, ...
        'EyeAbortPreX', NaN, 'EyeAbortPreY', NaN, 'HndAbortPreX', NaN, 'HndAbortPreY', NaN, ...
        'EyeAbortPostX', NaN, 'EyeAbortPostY', NaN, 'HndAbortPostX', NaN, 'HndAbortPostY', NaN, ...
        'WinEyeFixX', NaN, 'WinEyeFixY', NaN, 'WinEyeFixR', NaN, ...
        'WinHndFixX', NaN, 'WinHndFixY', NaN, 'WinHndFixR', NaN, ...
        'WinEyeTarX', NaN, 'WinEyeTarY', NaN, 'WinEyeTarR', NaN, ...
        'WinHndTarX', NaN, 'WinHndTarY', NaN, 'WinHndTarR', NaN, ...
        'WinEyeTar2X', NaN, 'WinEyeTar2Y', NaN, 'WinEyeTar2R', NaN, ...
        'WinHndTar2X', NaN, 'WinHndTar2Y', NaN, 'WinHndTar2R', NaN, ...
        'WinHndCueX', NaN, 'WinHndCueY', NaN, 'WinHndCueR', NaN, ...
        'WinHndCue2X', NaN, 'WinHndCue2Y', NaN, 'WinHndCue2R', NaN);

    [sp.WinEyeFixX, sp.WinEyeFixY, sp.WinEyeFixR] = get_window_xyz(trial, 'eye', 'fix');
    [sp.WinHndFixX, sp.WinHndFixY, sp.WinHndFixR] = get_window_xyz(trial, 'hnd', 'fix');
    [sp.WinEyeTarX, sp.WinEyeTarY, sp.WinEyeTarR] = get_window_xyz(trial, 'eye', 'tar', 1);
    [sp.WinEyeTar2X, sp.WinEyeTar2Y, sp.WinEyeTar2R] = get_window_xyz(trial, 'eye', 'tar', 2);
    [sp.WinHndTarX, sp.WinHndTarY, sp.WinHndTarR] = get_window_xyz(trial, 'hnd', 'tar', 1);
    [sp.WinHndTar2X, sp.WinHndTar2Y, sp.WinHndTar2R] = get_window_xyz(trial, 'hnd', 'tar', 2);
    [sp.WinHndCueX, sp.WinHndCueY, sp.WinHndCueR] = get_window_xyz(trial, 'hnd', 'cue', 1);
    [sp.WinHndCue2X, sp.WinHndCue2Y, sp.WinHndCue2R] = get_window_xyz(trial, 'hnd', 'cue', 2);

    [te, xe, ye, se] = get_aligned_stream_kinematics(trial, STATE, 'x_eye', 'y_eye', true, t_pre);
    [th, xh, yh, sh] = get_aligned_stream_kinematics(trial, STATE, 'x_hnd', 'y_hnd', true, t_pre);
    [sp.EyeFixMeanX, sp.EyeFixMeanY] = mean_in_state(te, xe, ye, se, STATE.FIX_HOL);
    [sp.HndFixMeanX, sp.HndFixMeanY] = mean_in_state(th, xh, yh, sh, STATE.FIX_HOL);
    [sp.EyeTarMeanX, sp.EyeTarMeanY] = mean_in_state(te, xe, ye, se, STATE.TAR_HOL);
    [sp.HndTarMeanX, sp.HndTarMeanY] = mean_in_state(th, xh, yh, sh, STATE.TAR_HOL);

    success = get_scalar_num_field(trial, 'success');
    if ~isnan(success) && success == 1
        return;
    end
    if isempty(aborted_state)
        aborted_state = get_trial_aborted_state(trial, STATE);
    end
    if isempty(abr_dur)
        abr_dur = get_aborted_state_duration(trial);
    end
    sp.AbortedState = aborted_state;
    sp.AbortedStateDuration = abr_dur;
    t_break = get_abort_break_time(trial, STATE, sp.AbortedState, sp.AbortedStateDuration);
    [sp.EyeAbortPreX, sp.EyeAbortPreY, sp.EyeAbortPostX, sp.EyeAbortPostY] = ...
        samples_around_time(te, xe, ye, t_break);
    [sp.HndAbortPreX, sp.HndAbortPreY, sp.HndAbortPostX, sp.HndAbortPostY] = ...
        samples_around_time(th, xh, yh, t_break);
end

function [x, y, r] = get_window_xyz(trial, effector, which, idx)
    x = NaN; y = NaN; r = NaN;
    if nargin < 4
        idx = 1;
    end
    if ~isfield(trial, effector), return; end
    S = trial.(effector);
    if ~isfield(S, which), return; end
    w = S.(which);
    if isempty(w) || idx < 1 || idx > numel(w)
        return;
    end
    w = w(idx);
    if isfield(w, 'x'), x = double(w.x(1)); end
    if isfield(w, 'y'), y = double(w.y(1)); end
    if isfield(w, 'radius'), r = double(w.radius(1)); end
end

function [mx, my] = mean_in_state(t, x, y, state, code)
    mx = NaN; my = NaN;
    if isempty(t) || isempty(state)
        return;
    end
    mask = state == code;
    if ~any(mask)
        return;
    end
    mx = mean(x(mask), 'omitnan');
    my = mean(y(mask), 'omitnan');
end

function t_break = get_abort_break_time(trial, STATE, aborted_state, abr_dur)
% Real break: aborted_state onset + aborted_state_duration (not ABORT stamp).
    t_break = NaN;
    if ~isnan(aborted_state) && ~isnan(abr_dur) && abr_dur >= 0
        t_state = get_state_event_onset(trial, aborted_state);
        if ~isnan(t_state)
            t_break = t_state + abr_dur;
            return;
        end
    end
    t_abort = get_state_event_onset(trial, STATE.ABORT);
    if ~isnan(t_abort)
        t_break = t_abort;
    end
end

function [x_pre, y_pre, x_post, y_post] = samples_around_time(t, x, y, t_break)
    x_pre = NaN; y_pre = NaN; x_post = NaN; y_post = NaN;
    if isempty(t) || isnan(t_break)
        return;
    end
    i_pre = find(t <= t_break, 1, 'last');
    i_post = find(t > t_break, 1, 'first');
    if ~isempty(i_pre)
        x_pre = x(i_pre); y_pre = y(i_pre);
    end
    if ~isempty(i_post)
        x_post = x(i_post); y_post = y(i_post);
    end
end

function [xh, yh] = get_target_hold_position(t, x, y, state, STATE, cfg)
    xh = NaN;
    yh = NaN;
    if isempty(t)
        return;
    end
    hold_mask = false(size(t));
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

function t_on = detect_speed_onset_near_fixation(t, x, y, t_go, cfg, t_tar_hol)
    t_on = NaN;
    if numel(t) < 4 || isnan(t_go)
        return;
    end
    dt = max(diff(t), eps);
    spd = [0; hypot(diff(x), diff(y)) ./ dt];

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
    if ~isnan(t_tar_hol)
        t_latest = min(t_latest, t_tar_hol);
    end

    idx = find(t >= t_earliest & t <= t_latest & ...
        spd >= speed_thr & dist < cfg.move_onset_max_disp, 1, 'first');
    if ~isempty(idx)
        t_on = t(idx);
    end
end

function t_detach = detect_fixation_detach_after_go(t, x, y, t_go, cfg, t_tar_hol)
    t_detach = NaN;
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
    if ~isnan(t_tar_hol)
        t_latest = min(t_latest, t_tar_hol);
    end

    idx = find(t >= t_earliest & t <= t_latest & ...
        hypot(x - x0, y - y0) >= cfg.fix_exit_radius, 1, 'first');
    if ~isempty(idx)
        t_detach = t(idx);
    end
end

function t_target = get_target_hold_onset_time(t, x, y, state, t_detach, t_tar_hol, cfg, STATE)
    t_target = NaN;
    if isnan(t_detach)
        return;
    end
    if ~isnan(t_tar_hol) && t_tar_hol >= t_detach
        t_target = t_tar_hol;
        return;
    end
    t_target = get_kinematic_target_arrival_time(t, x, y, state, t_detach, cfg, STATE);
end

function t_target = get_kinematic_target_arrival_time(t, x, y, state, t_detach, cfg, STATE)
    t_target = NaN;
    if isnan(t_detach)
        return;
    end
    [xh, yh] = get_target_hold_position(t, x, y, state, STATE, cfg);
    if isnan(xh) || isnan(yh)
        return;
    end
    onset_idx = find(t >= t_detach, 1, 'first');
    if isempty(onset_idx)
        return;
    end
    n_sustain = cfg.target_sustain_samples;
    d = hypot(x - xh, y - yh);
    for k = onset_idx:(numel(t) - n_sustain + 1)
        if all(d(k:(k + n_sustain - 1)) <= cfg.target_acq_radius)
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
        [parent, ~, ext] = fileparts(input_path);
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

function param = apply_name_value_pairs(param, args)
% Merge 'name', value pairs into param.
    if isempty(args)
        return;
    end
    if rem(numel(args), 2) ~= 0
        error('Optional inputs must be name/value pairs.');
    end
    valid = fieldnames(param);
    for k = 1:2:numel(args)
        name = args{k};
        if isstring(name)
            if ~isscalar(name)
                error('Parameter names must be scalar strings or char vectors.');
            end
            name = char(name);
        elseif ~ischar(name)
            error('Optional inputs must be name/value pairs.');
        end
        if ~any(strcmp(name, valid))
            error('Unknown parameter ''%s''. Valid: %s.', name, strjoin(valid, ', '));
        end
        param.(name) = args{k + 1};
    end
end

function [run_files, keep_ids] = apply_keep_runs(run_files, keep_runs)
% Keep files whose stem ends in _xx matching keep_runs. Empty keep_runs = all.
    keep_ids = [];
    if nargin < 2 || isempty(keep_runs)
        return;
    end
    keep_ids = parse_run_xx_ids(keep_runs, 'keep_runs');
    if isempty(keep_ids)
        error('keep_runs did not parse to any run _xx ids.');
    end
    n = numel(run_files);
    file_ids = NaN(n, 1);
    for i = 1:n
        file_ids(i) = run_id_from_filename(run_files{i});
    end
    keep_mask = false(n, 1);
    missing = {};
    for k = 1:numel(keep_ids)
        id = keep_ids(k);
        hit = file_ids == id;
        if ~any(hit)
            missing{end+1} = sprintf('%02d', id); %#ok<AGROW>
        else
            keep_mask = keep_mask | hit;
        end
    end
    if ~isempty(missing)
        found = format_run_suffix_tag(run_files);
        error('No .mat matching requested run _%s. Found: %s', ...
            strjoin(missing, ', _'), found);
    end
    run_files = run_files(keep_mask);
    run_files = run_files(:);
end

function ids = parse_run_xx_ids(val, who)
    ids = [];
    if isnumeric(val)
        ids = unique(round(val(:))', 'stable');
        ids = ids(~isnan(ids));
        return;
    end
    if isstring(val) || ischar(val)
        val = cellstr(val);
    elseif ~iscell(val)
        error('%s must be numeric _xx or char/string (''01'', ''01-03'', stem).', who);
    end
    for k = 1:numel(val)
        item = val{k};
        if isnumeric(item)
            ids = [ids, round(item(:)')]; %#ok<AGROW>
            continue;
        end
        s = strtrim(char(item));
        if isempty(s)
            continue;
        end
        [~, stem, ~] = fileparts(s);
        tok = regexp(stem, '_(\d+)$', 'tokens', 'once');
        if ~isempty(tok)
            ids(end+1) = str2double(tok{1}); %#ok<AGROW>
            continue;
        end
        parts = regexp(regexprep(stem, '^_+', ''), '[-_,\s]+', 'split');
        for p = 1:numel(parts)
            part = parts{p};
            if isempty(part)
                continue;
            end
            if isempty(regexp(part, '^\d{1,3}$', 'once'))
                error('Cannot parse run _xx from %s token ''%s''.', who, s);
            end
            ids(end+1) = str2double(part); %#ok<AGROW>
        end
    end
    ids = unique(ids, 'stable');
    ids = ids(~isnan(ids));
end

function id = run_id_from_filename(fpath)
    id = NaN;
    if isempty(fpath)
        return;
    end
    [~, stem, ~] = fileparts(fpath);
    tok = regexp(stem, '_(\d+)$', 'tokens', 'once');
    if ~isempty(tok)
        id = str2double(tok{1});
    end
end

function tag = format_run_suffix_tag(run_files)
    if isempty(run_files)
        tag = 'none';
        return;
    end
    parts = cell(numel(run_files), 1);
    for i = 1:numel(run_files)
        [~, stem, ~] = fileparts(run_files{i});
        tok = regexp(stem, '_(\d+)$', 'tokens', 'once');
        if isempty(tok)
            parts{i} = sprintf('%02d', i);
        else
            parts{i} = tok{1};
        end
    end
    tag = strjoin(parts, '-');
end

function s = format_run_id_list(ids)
    parts = cell(numel(ids), 1);
    for i = 1:numel(ids)
        parts{i} = sprintf('_%02d', ids(i));
    end
    s = strjoin(parts, ', ');
end

function [run_files, skipped_user_runs] = apply_skip_runs(run_files, skip_runs)
% Drop *_xx.mat. 1 / '01' / '_01' all mean filename suffix, not folder order.
    skipped_user_runs = {};
    if isempty(skip_runs)
        return;
    end
    skip_ids = parse_run_xx_ids(skip_runs, 'skip_runs');
    if isempty(skip_ids)
        error('skip_runs did not parse to any run _xx ids.');
    end
    n = numel(run_files);
    file_ids = NaN(n, 1);
    for i = 1:n
        file_ids(i) = run_id_from_filename(run_files{i});
    end
    skip_mask = false(n, 1);
    missing = {};
    for k = 1:numel(skip_ids)
        id = skip_ids(k);
        hit = file_ids == id;
        if ~any(hit)
            missing{end+1} = sprintf('%02d', id); %#ok<AGROW>
        else
            skip_mask = skip_mask | hit;
        end
    end
    if ~isempty(missing)
        found = format_run_suffix_tag(run_files);
        error('skip_runs: no .mat matching _%s. Found: %s', ...
            strjoin(missing, ', _'), found);
    end
    skipped_user_runs = run_files(skip_mask);
    skipped_user_runs = skipped_user_runs(:);
    run_files = run_files(~skip_mask);
    run_files = run_files(:);
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
        keep(i) = ~is_nonreach_trial(trials(i));
    end
    trials = trials(keep);
end

function tf = all_nonreach_trials(trials)
    tf = false;
    if isempty(trials)
        return;
    end
    tf = true;
    for i = 1:numel(trials)
        if ~is_nonreach_trial(trials(i))
            tf = false;
            return;
        end
    end
end

function tf = is_nonreach_trial(trial)
% Eye-only (effector==0) or fixation-like MP type (1, 8, 11, 12).
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
    if ~isnan(trial_type) && ismember(trial_type, [1, 8, 11, 12])
        tf = true;
    end
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
        [parent, ~, ext] = fileparts(input_path);
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

function [position, tar_x, tar_y] = get_target_pos(trial)
    position = NaN;
    tar_x = NaN;
    tar_y = NaN;
    if ~(isfield(trial, 'hnd') && isfield(trial.hnd, 'tar')) || isempty(trial.hnd.tar)
        return;
    end
    tar = trial.hnd.tar;
    idx = [];
    if isscalar(tar)
        idx = 1;
    elseif isfield(trial, 'target_selected') && numel(trial.target_selected) >= 2 && ...
            ~isnan(trial.target_selected(2))
        idx = trial.target_selected(2);
    end
    if isempty(idx) || idx < 1 || idx > numel(tar)
        return;
    end
    w = tar(idx);
    if isfield(w, 'x') && ~isempty(w.x)
        tar_x = double(w.x(1));
    end
    if isfield(w, 'y') && ~isempty(w.y)
        tar_y = double(w.y(1));
    end
    if isnan(tar_x) || ~isfield(trial.hnd, 'fix') || ~isfield(trial.hnd.fix, 'x')
        return;
    end
    fx = trial.hnd.fix.x;
    if tar_x < fx
        position = 1;
    elseif tar_x > fx
        position = 2;
    end
end

function tf = trial_reached_fixation(trial, STATE)
    tf = false;
    if ~isfield(trial, 'states') || isempty(trial.states)
        return;
    end
    states = trial.states(:);
    tf = any(states == STATE.FIX_ACQ | states == STATE.FIX_HOL);
end

function [del_hold, del_var, cue_hold, cue_var] = get_delay_timing_params(data, trials)
    del_hold = NaN;
    del_var = NaN;
    cue_hold = NaN;
    cue_var = NaN;
    candidates = cell(2, 1);
    nc = 0;
    if isfield(data, 'task') && isstruct(data.task) && isfield(data.task, 'timing')
        nc = 1;
        candidates{1} = data.task.timing;
    end
    for i = 1:min(numel(trials), 20)
        if isfield(trials(i), 'task') && isstruct(trials(i).task) && isfield(trials(i).task, 'timing')
            nc = nc + 1;
            candidates{nc} = trials(i).task.timing;
            break;
        end
    end
    candidates = candidates(1:nc);
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
    tbl = attach_empty_spatial_columns(tbl);
    tbl.MpTaskType = double([]);
    tbl.TarX = double([]);
    tbl.TarY = double([]);
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

function tbl = attach_empty_spatial_columns(tbl)
    names = { ...
        'AbortedState', 'AbortedStateDuration', ...
        'EyeFixMeanX', 'EyeFixMeanY', 'HndFixMeanX', 'HndFixMeanY', ...
        'EyeTarMeanX', 'EyeTarMeanY', 'HndTarMeanX', 'HndTarMeanY', ...
        'EyeAbortPreX', 'EyeAbortPreY', 'HndAbortPreX', 'HndAbortPreY', ...
        'EyeAbortPostX', 'EyeAbortPostY', 'HndAbortPostX', 'HndAbortPostY', ...
        'WinEyeFixX', 'WinEyeFixY', 'WinEyeFixR', ...
        'WinHndFixX', 'WinHndFixY', 'WinHndFixR', ...
        'WinEyeTarX', 'WinEyeTarY', 'WinEyeTarR', ...
        'WinHndTarX', 'WinHndTarY', 'WinHndTarR', ...
        'WinEyeTar2X', 'WinEyeTar2Y', 'WinEyeTar2R', ...
        'WinHndTar2X', 'WinHndTar2Y', 'WinHndTar2R', ...
        'WinHndCueX', 'WinHndCueY', 'WinHndCueR', ...
        'WinHndCue2X', 'WinHndCue2Y', 'WinHndCue2R'};
    n = height(tbl);
    for i = 1:numel(names)
        tbl.(names{i}) = NaN(n, 1);
    end
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
