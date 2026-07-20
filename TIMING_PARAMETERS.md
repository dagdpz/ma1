# Trial Structure Timing Parameters

## Overview
This document lists all timing-related parameters found in the monkeypsych trial structure from behavioral data recordings.

## 1. State-Based Timing Parameters

### Primary State Fields

**`states`** (array)
- **Type**: Integer array (e.g., `[1 2 3 6 8 4 5 20 21]`)
- **Description**: Sequence of state transitions that occurred during the trial
- **Usage**: Identifies which states were visited (in order)

**`states_onset`** (array, seconds)
- **Type**: Double array (absolute time in seconds)
- **Description**: Absolute timestamps for each state transition
- **Example**: `[10.070 10.678 11.154 11.627 11.838 13.040 13.539 13.840 13.856]`
- **Usage**: Calculate state durations, align events to state transitions

**`state`** (time series array)
- **Type**: Integer array (same length as position/time series)
- **Description**: State value at each sample point
- **Length**: Matches `x_hnd`, `y_hnd`, `x_eye`, `y_eye` arrays
- **Usage**: Identify state at any given time point in the trial

### State Definitions (from monkeypsych)

| State # | Name | Description |
|---------|------|-------------|
| 1 | INI_TRI | Initialize trial |
| 2 | FIX_ACQ | Fixation acquisition |
| 3 | FIX_HOL | Fixation hold |
| 4 | TAR_ACQ | Target acquisition |
| 5 | TAR_HOL | Target hold |
| 6 | CUE_ON | Cue on |
| 7 | MEM_PER | Memory period |
| 8 | DEL_PER | **Delay period** ⭐ |
| 9 | TAR_ACQ_INV | Target acquisition invisible |
| 10 | TAR_HOL_INV | Target hold invisible |
| 11 | MAT_ACQ | Target acquisition in sample to match |
| 12 | MAT_HOL | Target hold in sample to match |
| 13 | MAT_ACQ_MSK | Target acquisition masked |
| 14 | MAT_HOL_MSK | Target hold masked |
| 15 | SEN_RET | Return to sensors (Poffenberger) |
| 19 | ABORT | Trial aborted |
| 20 | SUCCESS | Trial successful |
| 21 | REWARD | Reward delivery |
| 50 | ITI | Inter-trial interval |
| 99 | CLOSE | Trial closed |

### Calculating State Durations
```matlab
% From states_onset array
state_durations = diff(states_onset);  % Duration of each state
```

### ⭐ Delay Period Duration (State 8: DEL_PER)

**The delay period duration is a critical timing parameter** that measures the time the monkey waits between cue presentation and target appearance.

**How to extract delay period duration:**

```matlab
% Method 1: Direct calculation from states_onset
delay_idx = find(trial.states == 8, 1);  % Find delay period state
if ~isempty(delay_idx) && delay_idx < length(trial.states_onset)
    delay_duration = trial.states_onset(delay_idx + 1) - trial.states_onset(delay_idx);
    fprintf('Delay period duration: %.3f s\n', delay_duration);
end

% Method 2: Using state_durations array
state_durations = diff(trial.states_onset);
delay_idx = find(trial.states == 8, 1);
if ~isempty(delay_idx) && delay_idx <= length(state_durations)
    delay_duration = state_durations(delay_idx);
end

% Method 3: Using the helper function
timing = ma1_extract_timing_params(trial);
delay_duration = timing.delay_duration;  % Already calculated
```

**Typical values:**
- **Range**: ~0.8 - 1.2 seconds (varies by task design)
- **Mean**: ~1.0 - 1.1 seconds (example from session 20260116)
- **Note**: Not all trials contain a delay period (state 8 may be absent)

**State sequence context:**
- Delay period typically occurs after cue presentation (state 6: CUE_ON)
- Common sequence: `[... 6 (CUE_ON) → 8 (DEL_PER) → 4 (TAR_ACQ) ...]`
- The delay duration is the time from entering state 8 to exiting state 8

**Example from actual data:**
```matlab
% Trial with delay period
states: [1 2 3 6 8 4 5 20 21]
states_onset: [10.070 10.678 11.154 11.627 11.838 13.040 ...]
% Delay period: state 8 from 11.838s to 13.040s
delay_duration = 13.040 - 11.838 = 1.202 seconds
```

## 2. Time Series Arrays

### Position/Behavioral Data Arrays
All arrays have the same length (number of samples varies by trial):

**`x_hnd`**, **`y_hnd`** (arrays)
- **Type**: Double arrays
- **Description**: Hand position (x, y coordinates) at each sample
- **Length**: Variable (typically 1000-10000 samples depending on trial duration)
- **Sampling**: Variable rate (~400-1200 Hz, depends on trial)

**`x_eye`**, **`y_eye`** (arrays)
- **Type**: Double arrays
- **Description**: Eye position (x, y coordinates) at each sample
- **Length**: Same as `x_hnd`, `y_hnd`

**`tSample_from_time_start`** (array, seconds)
- **Type**: Double array
- **Description**: Time of each sample relative to trial start
- **Range**: Typically `[0, trial_duration]` seconds
- **Usage**: Convert sample indices to time, align with state transitions
- **Note**: First value may not be exactly 0 (depends on recording start)

### Additional Time Series (if available)
- **`sen_L`**, **`sen_R`**: Sensor data (left/right)
- **`jaw`**: Jaw position
- **`body`**: Body position

## 3. Event Timing Parameters

### Trial Start Time
**`timestamp`** (array)
- **Type**: Integer array `[YYYY MM DD HH MM SS]`
- **Description**: Absolute timestamp of trial start
- **Example**: `[2026 1 16 9 25 50]` = January 16, 2026, 9:25:50 AM
- **Usage**: Synchronize across trials, calculate inter-trial intervals

### Reward Timing
**`reward_time`** (scalar, seconds)
- **Type**: Double
- **Description**: Time of reward delivery relative to trial start
- **Value**: `0` if no reward, `>0` if reward delivered
- **Example**: `0.220` = reward at 220 ms after trial start
- **Usage**: Analyze reward timing, calculate reaction times

**`rewarded`** (scalar)
- **Type**: Logical/Integer (0/1)
- **Description**: Whether trial was rewarded

**`reward_size`** (scalar)
- **Type**: Double
- **Description**: Size of reward (if applicable)

**`reward_prob`** (scalar)
- **Type**: Double
- **Description**: Reward probability for this trial

**`reward_selected`** (scalar)
- **Type**: Integer
- **Description**: Which reward was selected

## 4. Abort Timing Parameters

**`aborted_state`** (scalar)
- **Type**: Integer or NaN
- **Description**: State number where trial was aborted
- **Value**: State number (e.g., `2`, `19`) or `-1`/`NaN` if not aborted
- **Usage**: Identify which phase of trial failed

**`aborted_state_duration`** (scalar, seconds)
- **Type**: Double
- **Description**: Duration spent in the aborted state before trial termination
- **Value**: Duration in seconds, or `-1`/`NaN` if not aborted
- **Example**: `0.251` = aborted after 251 ms in that state

**`abort_code`** (scalar/string)
- **Type**: Integer or string
- **Description**: Code indicating reason for abort (if available)

## 5. Microstimulation Timing Parameters

**`microstim`** (scalar)
- **Type**: Logical/Integer (0/1)
- **Description**: Whether microstimulation was delivered in this trial

**`microstim_start`** (scalar, seconds)
- **Type**: Double or NaN
- **Description**: Start time of microstimulation relative to trial start
- **Value**: Time in seconds, or `NaN` if no microstim

**`microstim_end`** (scalar, seconds)
- **Type**: Double or NaN
- **Description**: End time of microstimulation relative to trial start
- **Value**: Time in seconds, or `NaN` if no microstim

**`microstim_interval`** (array)
- **Type**: Array or NaN
- **Description**: Microstimulation interval specification (if available)

**`microstim_state`** (scalar)
- **Type**: Integer or NaN
- **Description**: State during which microstimulation occurred

## 6. Trial Metadata (Timing-Related)

**`trial_number`** (scalar)
- **Type**: Integer
- **Description**: Sequential trial number within the run

**`n`** (scalar)
- **Type**: Integer
- **Description**: Trial number (may differ from `trial_number`)

**`completed`** (scalar)
- **Type**: Logical/Integer (0/1)
- **Description**: Whether trial completed (reached end state)

**`success`** (scalar)
- **Type**: Logical/Integer (0/1)
- **Description**: Whether trial was successful (`1`) or failed (`0`)

**`manual_success`** (scalar)
- **Type**: Logical/Integer (0/1)
- **Description**: Manually marked as successful (if applicable)

## 7. Sampling Rate Information

### Implied Sampling Rate
The sampling rate can be calculated from the data:
```matlab
sampling_rate = length(trial.x_hnd) / trial.states_onset(end);
```

**Note**: Sampling rate varies between trials (typically 400-1200 Hz), likely due to:
- Variable trial durations
- Different recording conditions
- System load variations

### TDT Stream Timing (if available)
Some trials may contain TDT (Tucker-Davis Technologies) timing streams:
- **`TDT_state_onsets`**: TDT-aligned state onsets
- **`TDT_RWRD_samplingrate`**: Reward stream sampling rate
- **`TDT_ECG1_samplingrate`**: ECG stream sampling rate
- **`TDT_stream_duration_from_state2`**: Duration from state 2

## 8. Common Timing Calculations

### Trial Duration
```matlab
trial_duration = trial.states_onset(end) - trial.states_onset(1);
```

### State Durations
```matlab
state_durations = diff(trial.states_onset);
```

### Time to Specific State
```matlab
% Find time to reach state 4 (target acquisition)
state4_idx = find(trial.states == 4, 1);
if ~isempty(state4_idx)
    time_to_state4 = trial.states_onset(state4_idx);
end
```

### Reaction Time (for reach tasks)
```matlab
% Time from cue (state 6) to target acquisition (state 4)
cue_idx = find(trial.states == 6, 1);
target_idx = find(trial.states == 4, 1);
if ~isempty(cue_idx) && ~isempty(target_idx) && target_idx > cue_idx
    reaction_time = trial.states_onset(target_idx) - trial.states_onset(cue_idx);
end
```

### Movement Time
```matlab
% Time from target acquisition (state 4) to target hold (state 5)
acq_idx = find(trial.states == 4, 1);
hold_idx = find(trial.states == 5, 1);
if ~isempty(acq_idx) && ~isempty(hold_idx) && hold_idx > acq_idx
    movement_time = trial.states_onset(hold_idx) - trial.states_onset(acq_idx);
end
```

### ⭐ Delay Period Duration (State 8: DEL_PER)

**The delay period duration is the time spent waiting between cue presentation and target appearance.**

```matlab
% Method 1: Direct calculation from states_onset
delay_idx = find(trial.states == 8, 1);  % Find delay period state (DEL_PER)
if ~isempty(delay_idx) && delay_idx < length(trial.states_onset)
    delay_duration = trial.states_onset(delay_idx + 1) - trial.states_onset(delay_idx);
    fprintf('Delay period duration: %.3f s\n', delay_duration);
else
    fprintf('No delay period in this trial\n');
end

% Method 2: Using state_durations array
state_durations = diff(trial.states_onset);
delay_idx = find(trial.states == 8, 1);
if ~isempty(delay_idx) && delay_idx <= length(state_durations)
    delay_duration = state_durations(delay_idx);
end

% Method 3: Using the helper function (recommended)
timing = ma1_extract_timing_params(trial);
delay_duration = timing.delay_duration;  % Already calculated, NaN if no delay
```

**Key Points:**
- **State**: 8 (DEL_PER - Delay period)
- **Typical range**: 0.8 - 1.2 seconds (varies by experimental design)
- **Typical mean**: ~1.0 - 1.1 seconds (example from session 20260116)
- **Not all trials contain delay**: Some trials may not have state 8
- **State sequence**: Typically occurs as `[... 6 (CUE_ON) → 8 (DEL_PER) → 4 (TAR_ACQ) ...]`

**Example from actual data:**
```matlab
% Trial with delay period
trial.states = [1 2 3 6 8 4 5 20 21];
trial.states_onset = [10.070 10.678 11.154 11.627 11.838 13.040 13.539 13.840 13.856];

% Delay period: state 8 from 11.838s to 13.040s
delay_duration = 13.040 - 11.838 = 1.202 seconds
```

## 9. Example: Complete Timing Analysis

```matlab
% Load trial
data = load('Fen2026-01-16_01.mat');
trial = data.trial(2);  % Example successful trial

% Basic timing info
fprintf('Trial duration: %.3f s\n', trial.states_onset(end) - trial.states_onset(1));
fprintf('Number of samples: %d\n', length(trial.x_hnd));
fprintf('Sampling rate: %.1f Hz\n', length(trial.x_hnd) / trial.states_onset(end));

% State sequence
fprintf('State sequence: %s\n', mat2str(trial.states));
fprintf('State onsets: %s\n', mat2str(trial.states_onset, 3));

% State durations
durations = diff(trial.states_onset);
for i = 1:length(durations)
    fprintf('State %d duration: %.3f s\n', trial.states(i), durations(i));
end

% ⭐ Delay period duration (if present)
delay_idx = find(trial.states == 8, 1);
if ~isempty(delay_idx) && delay_idx < length(trial.states_onset)
    delay_duration = trial.states_onset(delay_idx + 1) - trial.states_onset(delay_idx);
    fprintf('Delay period duration: %.3f s\n', delay_duration);
end

% Reward timing
if trial.reward_time > 0
    fprintf('Reward delivered at: %.3f s\n', trial.reward_time);
end

% Abort info (if applicable)
if trial.aborted_state > 0
    fprintf('Aborted in state %d after %.3f s\n', ...
        trial.aborted_state, trial.aborted_state_duration);
end
```

## 10. Notes and Caveats

1. **Variable Sampling Rates**: Sampling rate is not constant across trials. Always calculate from trial data.

2. **Absolute vs Relative Times**: 
   - `states_onset`: Absolute times (from run start)
   - `tSample_from_time_start`: Relative to trial start
   - `reward_time`: Relative to trial start

3. **State Alignment**: States in `states` array correspond to transitions, while `state` array contains continuous state values.

4. **Missing Data**: Some timing fields may be `NaN` or `-1` if not applicable (e.g., no microstim, no abort).

5. **Trial Start**: First sample may not align exactly with state 1 onset due to recording initialization.

6. **Failed vs Successful Trials**: Failed trials typically have fewer states and shorter durations.

## References

- State definitions from `ma1_page_thru_trials_v3.m` and `ma1_process_one_run_pulv_ephys_dataset1.m`
- Timing calculations based on analysis of actual trial data from session `20260116`
