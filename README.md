# ma1 - MonkeyPsych Analysis 1

MATLAB toolbox for reading, visualizing, and analyzing behavioral data from **MonkeyPsych** `.mat` run files, with optional integration of **TDT ephys** streams and **em** toolbox saccade detection.

Originally developed for DAG ephys analysis (2016); actively extended for hand-reach tasks and daily session summaries.

## Requirements

- MATLAB (R2016b+; Live Script guidelines need R2025a+)
- [MonkeyPsych](https://github.com/igor-kagan/monkeypsych) run files (`trial` struct array in each `.mat`)
- **[em](https://github.com/igor-kagan/em)** toolbox - saccade/blink detection (`em_saccade_blink_detection`)
- **ig** toolbox - plotting helpers (`ig_add_multiple_vertical_lines`, `ig_make_raster`, etc.)
- **DAG toolbox** - `checkstruct`, `findfiles` (pulvinar ephys pipeline only)
- TDT-combined `.mat` files for ephys/PSTH functions (`TDT_eNeu_t`, `TDT_state_onsets`, ...)
- Excel I/O for sorting tables and `ma1_analyze_reaches_session` export

```matlab
addpath('path/to/ma1');
addpath('path/to/em');
addpath('path/to/ig');
```

## Data format

Each run file contains a `trial` struct array. Key fields used across ma1:

| Field | Description |
|-------|-------------|
| `states`, `states_onset` | State transition sequence and absolute times (s) |
| `state` | Per-sample state label (same length as kinematics) |
| `x_eye`, `y_eye`, `x_hnd`, `y_hnd` | Eye/hand position time series |
| `tSample_from_time_start` | Sample times relative to trial start |
| `success`, `choice`, `effector`, `reach_hand` | Outcome, free (1) vs instructed (0), effector, hand used |
| `microstim`, `reward_time`, `aborted_state` | Stimulation and abort metadata |

See [TIMING_PARAMETERS.md](TIMING_PARAMETERS.md) for full timing-field reference and state definitions.

### MonkeyPsych state codes (common)

| # | Name | # | Name |
|---|------|---|------|
| 1 | INI_TRI | 8 | DEL_PER |
| 2 | FIX_ACQ | 9-14 | invisible/masked targets |
| 3 | FIX_HOL | 19 | ABORT |
| 4 | TAR_ACQ | 20 | SUCCESS |
| 5 | TAR_HOL | 21 | REWARD |
| 6 | CUE_ON | 50 | ITI |
| 7 | MEM_PER | 99 | CLOSE |

---

## Function reference

### Trial browsers (`ma1_page_thru_trials_*`)

Interactive trial-by-trial viewers. Common arguments:

- `runpath` - path to `.mat` run file
- `list_successful_only` - `0` all trials, `1` successful only, `-1` failed only
- `plot_trials` - `1` to open per-trial figure(s)

Navigate with keyboard (space / arrow keys) inside the figure.

| Function | Purpose |
|----------|---------|
| `ma1_page_thru_trials` | Original ephys browser: PSTH, rasters, eye/hand traces, TDT state alignment |
| `ma1_page_thru_trials_v2` | v1 + trial timing overlays |
| `ma1_page_thru_trials_v3` | **Recommended ephys browser** - saccade detection, trial sorting, task-specific windows, summary PSTHs by hemifield and choice type |
| `ma1_page_thru_trials_ephys` | Lightweight ephys view: kinematics + TDT reward TTL + optional saccades |
| `ma1_page_thru_trials_simple` | Eye-fixation task: per-trial traces, 2D endpoint summary, optional eye recalibration |
| `ma1_page_thru_trials_binoriv` | Binocular rivalry - auto-detects fixation vs directed-saccade variant from `task.custom_conditions` |
| `ma1_page_thru_trials_binoriv_fixation` | Binoriv fixation variant (legacy state numbers) |
| `ma1_page_thru_trials_binoriv_task` | Binoriv task viewer (newer state codes: fix hold = 34) |
| `ma1_list_run_trials` | Print trial index, task type, success, microstim to console |

```matlab
% Ephys PSTH + rasters (instructed=blue, choice=red)
out = ma1_page_thru_trials_v3('Lincombined2015-05-06_03.mat', 1, 1);

% Binoriv: fixation-hold summary only
ma1_page_thru_trials_binoriv(filepath, 0, 0, 0, 1);

% Binoriv: 2D plot of failed trials
ma1_page_thru_trials_binoriv(filepath, -1, 0, 1, 0);
```

#### Binoriv 2D summary legend

- Light red circle - fixation window around fixation spot / target
- Blue - gaze before fixation hold
- Green - gaze during fixation hold
- Red - gaze after fixation break
- Black - gaze between saccade/fixation phases
- Black dot - last fixation-hold sample

#### Saccade detection settings

Pass a custom settings `.m` filename (e.g. `'ma1_em_settings_monkey_220Hz'`) as the last argument, or use the bundled 220 Hz monkey settings:

```matlab
% ma1_em_settings_monkey_220Hz.m - SacOnsetVelThr=100, SacOffsetVelThr=30, etc.
```

---

### Hand-reach analysis

Consolidated into two entry points (older `ma1_reaches_analyze*` / `ma1_analyze_reaches_by_hemifield` removed):

| Function | Scope | Output |
|----------|-------|--------|
| `ma1_analyze_reaches_run` | Single run, vectorized | Console stats + struct `out` (hand/target, choice vs instructed) |
| `ma1_analyze_reaches_session` | **Full day** (folder or single run) | Per-block + day-summary figures and Excel |

**Hand/target coding:** `reach_hand` 1 = left, 2 = right; target position 1 = left, 2 = right.

**Combination labels:** `LL`, `LR`, `RL`, `RR` = left/right hand x left/right target.

```matlab
% Quick stats for one run
out = ma1_analyze_reaches_run('Fen2026-01-16_01.mat');

% Full daily analysis (auto-detects runs, skips eye-calibration-only blocks)
details = ma1_analyze_reaches_session('Y:\Data\DAG\Maria\20260116', 'Fen');
% details.excel_fullpath, details.plot_files, details.day_trials_table, ...
```

#### `ma1_analyze_reaches_session` timing metrics (successful trials)

Two independent epochs:

| Metric | Epoch | Definition |
|--------|-------|------------|
| `RTFixToSensorRelease` | Fixation | Fixation acquired -> home-sensor release |
| `MTSensorToFixHold` | Fixation | Sensor release -> fixation hold onset |
| `RTGoToMovement` | Reach | Go cue (TAR_ACQ) -> hand leaves screen fixation |
| `MTMovementToTarget` | Reach | Movement onset -> target hold |

Output directory: `Y:\Data\Behavior_analysis\{animal}\{animal}_{yyyy-mm-dd}\`

---

### Timing utilities

| Function | Purpose |
|----------|---------|
| `ma1_extract_timing_params` | Extract state durations, sampling rate, reward/abort/microstim timing from one `trial` struct |
| `ma1_check_timing_streams` | Align and plot TDT timing streams (ECG, state onsets) across trials; optional external ECG `.mat` |

```matlab
data = load('Fen2026-01-16_01.mat');
timing = ma1_extract_timing_params(data.trial(5));
timing.delay_duration   % state 8 (DEL_PER) duration, NaN if absent
timing.trial_duration
```

---

### Pulvinar ephys dataset (legacy, Linus/Curius 2015-2016)

Batch pipeline for dPul_r memory/direct saccade datasets with spike sorting tables.

| Function | Purpose |
|----------|---------|
| `ma1_process_one_run_pulv_ephys_dataset1` | Process one combined TDT run: PSTHs, rasters, spatial tuning, FR epochs |
| `ma1_process_pulv_ephys_dataset1` | Batch over predefined file lists (`Linus_direct_ds1`, `Linus_memory_ds1`, ...) |
| `ma1_analyze_pulv_ephys_dataset1` | Query analysis database Excel (`Linus_dPul_r_ds1_direct_saccade`, ...) |
| `ma1_get_unit_from_sorting_table` | Look up neuron metadata (SNR, depth, coordinates) from sorting Excel |
| `ma1_find_runs` | Filter a file list by task type and quality criteria |
| `ma1_custom_settings_example` | Template settings struct for `ma1_process_one_run_pulv_ephys_dataset1` |

```matlab
[n_unit, out] = ma1_process_one_run_pulv_ephys_dataset1( ...
    'Lincombined2015-05-08_08_block_01.mat', 'ma1_custom_settings_example');

ma1_process_pulv_ephys_dataset1('Linus_direct_ds1');
```

---

### Other

| Function | Purpose |
|----------|---------|
| `ma1_choice_bias_microstim` | Left/right target preference in choice trials, split by microstim on/off |
| `ma1_em_settings_monkey_220Hz` | Settings cell array for `em_saccade_blink_detection` at 220 Hz |

---

## Typical workflows

### Inspect a single behavioral run
```matlab
ma1_list_run_trials('Fen2026-01-16_01.mat', 0);          % list all trials
ma1_page_thru_trials_simple('Fen2026-01-16_01.mat', 1, 1); % browse successful trials
```

### Analyze a hand-reach session
```matlab
% Single run
out = ma1_analyze_reaches_run('/path/to/Fen2026-01-16_01.mat');

% Full day (all blocks)
details = ma1_analyze_reaches_session('/path/to/session_folder', 'Fen');
open(details.excel_fullpath);
```

### Ephys + behavior (combined TDT files)
```matlab
out = ma1_page_thru_trials_v3('Lincombined2015-05-06_03.mat', 1, 1);
```

### Check trial timing
```matlab
timing = ma1_extract_timing_params(data.trial(k));
```

---

## File index

```
ma1_page_thru_trials.m              % ephys browser (original)
ma1_page_thru_trials_v2.m           % ephys browser v2
ma1_page_thru_trials_v3.m           % ephys browser v3 (recommended)
ma1_page_thru_trials_ephys.m        % lightweight ephys viewer
ma1_page_thru_trials_simple.m       % fixation eye-movement viewer
ma1_page_thru_trials_binoriv.m      % binocular rivalry (auto task variant)
ma1_page_thru_trials_binoriv_fixation.m
ma1_page_thru_trials_binoriv_task.m
ma1_list_run_trials.m
ma1_analyze_reaches_run.m           % single-run reach stats
ma1_analyze_reaches_session.m       % daily reach analysis (main)
ma1_extract_timing_params.m
ma1_check_timing_streams.m
ma1_process_one_run_pulv_ephys_dataset1.m
ma1_process_pulv_ephys_dataset1.m
ma1_analyze_pulv_ephys_dataset1.m
ma1_get_unit_from_sorting_table.m
ma1_find_runs.m
ma1_choice_bias_microstim.m
ma1_em_settings_monkey_220Hz.m
ma1_custom_settings_example.m
TIMING_PARAMETERS.md
```

## See also

- [TIMING_PARAMETERS.md](TIMING_PARAMETERS.md) - trial struct timing fields, state durations, delay-period extraction
- [em toolbox](https://github.com/igor-kagan/em) - saccade detection used by page-thru and pulv functions
- [MonkeyPsych](https://github.com/igor-kagan/monkeypsych) - behavioral recording system that produces the input `.mat` files
