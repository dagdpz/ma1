function ma1_page_thru_trials_simple(runpath, list_successful_only, plot_trials, plot_2D, plot_summary, recalibrate, detect_saccades, detect_saccades_custom_settings)

% examples:
% ma1_page_thru_trials_simple('Y:\Data\Linus\20220322\Lin2022-03-22_05.mat',0,0,0,1); % plot fixation hold summary only
% ma1_page_thru_trials_simple('Y:\Data\Linus\20220322\Lin2022-03-22_05.mat',-1,0,1,0); % plot 2D failed trials
% ma1_page_thru_trials_simple('Y:\Data\Bacchus\20230615\Bac2023-06-15_02.mat',0,0,0,3,1); % recalibrate eye pos 


if nargin < 2,
    list_successful_only = 0; % if -1, list failed only
end

if nargin < 3,
    plot_trials = 0;
end

if nargin < 4,
    plot_2D = 0;
end

if nargin < 5,
    plot_summary = 0; % if 1, plot only the last sample of fixaton hold, if 2, plot all samples (same color), if 3, plot mean of each trial (different color)
end

if nargin < 6,
   recalibrate = 0; % if 1, re-do calibration, if 2, use previously saved calibration (last_eye_recal.mat)
end

if nargin < 7,
    detect_saccades = 0;
end

if nargin < 8,
    detect_saccades_custom_settings = '';
end

load(runpath);
disp(runpath);

run_folder = fileparts(runpath);


if plot_trials,
    hf = figure('Name','Plot trial','CurrentChar',' ','Position',[600 500 600 500]);
end

if plot_summary || plot_2D,
    axes = [-10 10];
end

if plot_2D
    hf2D = figure('Name','Plot 2D','CurrentChar',' ','Position',[1200 500 500 500]);
end

if recalibrate
    plot_summary = 3;
end

for k = 1:length(trial),
    
    
    if 1 % align time axis to trial start
        trial(k).states_onset = trial(k).states_onset - trial(k).tSample_from_time_start(1);
        trial(k).tSample_from_time_start = trial(k).tSample_from_time_start - trial(k).tSample_from_time_start(1);
    end
    
    
    if plot_summary || plot_2D,
        
        idx_before_fix_hold = find(trial(k).state < 3);
        idx_during_fix_hold = find(trial(k).state == 3);
        idx_after_fix_hold = find(trial(k).state > 3);
        
        
        if ~isempty(idx_during_fix_hold),
            last_fix_hold(k).x = trial(k).x_eye(idx_during_fix_hold(end));
            last_fix_hold(k).y = trial(k).y_eye(idx_during_fix_hold(end));
            all_fix_hold(k).x = trial(k).x_eye(idx_during_fix_hold);
            all_fix_hold(k).y = trial(k).y_eye(idx_during_fix_hold);
            
            fix_hold_dur(k) = trial(k).tSample_from_time_start(idx_during_fix_hold(end)) - trial(k).tSample_from_time_start(idx_during_fix_hold(1)-1);
            
            
            
        else
            last_fix_hold(k).x = NaN;
            last_fix_hold(k).y = NaN;
            all_fix_hold(k).x = NaN;
            all_fix_hold(k).y = NaN;
            
            fix_hold_dur(k) = 0;
            
        end
        
        
        
        trial_fix_window(k, :) = [trial(k).eye.fix.pos];
        
    end
    
    
    
    if (list_successful_only == 1 && trial(k).success) || (list_successful_only == -1 && ~trial(k).success) || list_successful_only==0
        
        
        if plot_trials,
            figure(hf);
            subplot(2,1,1); hold on;
            title(sprintf('Trial %d [%d]',k,trial(k).success));
            
            plot(trial(k).tSample_from_time_start,trial(k).state,'k');
            plot(trial(k).tSample_from_time_start,trial(k).x_eye,'g');
            plot(trial(k).tSample_from_time_start,trial(k).y_eye,'m');
            ig_add_multiple_vertical_lines(trial(k).states_onset,'Color','k');
            ylabel('Eye position, states');
            
            
            if detect_saccades,
                if ~isempty(detect_saccades_custom_settings),
                    em_saccade_blink_detection(trial(k).tSample_from_time_start,trial(k).x_eye,trial(k).y_eye,...
                        detect_saccades_custom_settings);
                else
                    em_saccade_blink_detection(trial(k).tSample_from_time_start,trial(k).x_eye,trial(k).y_eye,...
                        'Downsample2Real',0,'Plot',true,'OpenFigure',true);
                end
            end
            
            
            
            figure(hf);
            subplot(2,1,2)
            plot(trial(k).tSample_from_time_start,[NaN; diff(trial(k).tSample_from_time_start)],'k.');
            ylabel('Sampling interval');
            
        end
        
        
        if plot_trials,
            figure(hf);
            ig_set_all_axes('Xlim',[trial(k).tSample_from_time_start(1) trial(k).tSample_from_time_start(end)]);
            
            
            
            if ~plot_2D
                drawnow; pause;
                if get(gcf,'CurrentChar')=='q',
                    % close;
                    break;
                end
                clf(hf);
            end
        end
        
        if plot_2D,
            figure(hf2D);
            
            w = nsidedpoly(100, 'Center', [trial(k).eye.fix.x trial(k).eye.fix.y], 'Radius', trial(k).eye.fix.radius); plot(w, 'FaceColor', 'r'); hold on;
            
            plot(trial(k).x_eye,trial(k).y_eye,'k-','LineWidth',0.1);
            plot(trial(k).x_eye(idx_before_fix_hold),trial(k).y_eye(idx_before_fix_hold),'b-','LineWidth',0.2);
            plot(trial(k).x_eye(idx_during_fix_hold),trial(k).y_eye(idx_during_fix_hold),'g-','LineWidth',0.2);
            plot(trial(k).x_eye(idx_after_fix_hold),trial(k).y_eye(idx_after_fix_hold),'r-','LineWidth',0.2);
            plot(trial(k).x_eye(idx_before_fix_hold),trial(k).y_eye(idx_before_fix_hold),'b.','MarkerSize',1);
            plot(trial(k).x_eye(idx_during_fix_hold),trial(k).y_eye(idx_during_fix_hold),'g.','MarkerSize',1);
            if ~isempty(idx_during_fix_hold),
                plot(trial(k).x_eye(idx_during_fix_hold(end)),trial(k).y_eye(idx_during_fix_hold(end)),'k.','MarkerSize',15); % plot last sample of fixation hold
            end
            plot(trial(k).x_eye(idx_after_fix_hold),trial(k).y_eye(idx_after_fix_hold),'r.','MarkerSize',1);
            
            
            axis equal
            set(gca,'Xlim',axes,'Ylim',axes);
            title(sprintf('Trial %d [%d]',k,trial(k).success));
            drawnow; pause;
            
            if get(gcf,'CurrentChar')=='q',
                % close;
                break;
            end
            clf(hf2D);
            
            if plot_trials,
                clf(hf);
            end
        end
        
        
        
        
    end
    
end % for each trial


if plot_summary,
    
    
    idx_succ		= find([trial.success]==1);
    idx_fail		= find([trial.success]==0);
    
    % for eye pos recalibration
    TTx = zeros(length(idx_succ),1);
    TTy = TTx;
    Gx = TTx;
    Gy = TTx;
    
    
    figure('Position',[300 300 600 600]);
    
    uWindows = unique(trial_fix_window, 'rows');
    uWindows = uWindows(uWindows(:,4)<10,:); % remove trials with large windows
    
    uWindows_colors = jet(size(uWindows,1));
    
    for k=1:size(uWindows,1),
        w = nsidedpoly(100, 'Center', [uWindows(k,1) uWindows(k,2)], 'Radius', uWindows(k,4)); plot(w, 'FaceColor', [0.9 0.9 0.9]); hold on;
        plot(uWindows(k,1),uWindows(k,2),'ko');
    end
    
    if plot_summary == 1,
        plot([last_fix_hold(idx_succ).x],[last_fix_hold(idx_succ).y],'g.','MarkerSize',5); % plot last sample of fixation hold
        plot([last_fix_hold(idx_fail).x],[last_fix_hold(idx_fail).y],'r.','MarkerSize',5); % plot last sample of fixation hold
        
    elseif plot_summary == 2,
        cellArray_x = {all_fix_hold(idx_succ).x};
        cellArray_y = {all_fix_hold(idx_succ).y};
        plot(vertcat(cellArray_x{:}),vertcat(cellArray_y{:}),'g.','MarkerSize',5); % plot all samples of fixation hold
        % plot([all_fix_hold(idx_fail).x],[all_fix_hold(idx_fail).y],'r.','MarkerSize',2); % plot all samples of fixation hold
        
    elseif plot_summary == 3
        for k = 1:length(idx_succ) % for each succ. trial
            t = idx_succ(k); % trial number
            for w = 1:length(uWindows)
                if trial_fix_window(t,1) == uWindows(w,1) && trial_fix_window(t,2) == uWindows(w,2),
                    Gx(k) = mean(all_fix_hold(t).x);
                    Gy(k) = mean(all_fix_hold(t).y);
                    TTx(k) = uWindows(w,1);
                    TTy(k) = uWindows(w,2);
                    plot(Gx(k),Gy(k),'k.','MarkerSize',5,'Color',uWindows_colors(w,:));
                end
            end
        end
        
        if recalibrate % perform nonlinear eye pos recalibration
            if recalibrate == 1
                % transformationType: 'NonreflectiveSimilarity' | 'Similarity' | 'Affine' | 'Projective' | 'pwl'
                % or 'polynomial'
                transformationType = 'polynomial';
                switch transformationType
                    case 'polynomial'
                        tform = fitgeotrans([TTx TTy], [Gx Gy], transformationType,2);
                    otherwise
                        tform = fitgeotrans([TTx TTy], [Gx Gy], transformationType);
                end
                save([run_folder filesep 'last_eye_recal.mat'],'tform');
                disp(['saved ' run_folder filesep 'last_eye_recal.mat']);
                
            elseif recalibrate == 2
                if exist([run_folder filesep 'last_eye_recal.mat'],'file')
                        load([run_folder filesep 'last_eye_recal.mat']);
                        disp(['loaded ' run_folder filesep 'last_eye_recal.mat']);
                end
            end
            tic
            recG = transformPointsInverse(tform, [Gx Gy]);
            toc
            plot(recG(:,1),recG(:,2),'k.');
            
        end
            
        
        
    end
    
    axis equal
    set(gca,'Xlim',axes,'Ylim',axes);
    title(sprintf('%s %d succ. %d failed trials',runpath,length(idx_succ),length(idx_fail)),'Interpreter','none');
    
    
    figure('Position',[300 300 600 600]);
    bins = [0 0.01:0.1:(task.timing.fix_time_hold + task.timing.fix_time_hold_var)];
    histSuccDur = hist(fix_hold_dur(idx_succ),bins);
    histFailDur = hist(fix_hold_dur(idx_fail),bins);
    
    plot(bins,ig_hist2per(histSuccDur),'g','LineWidth',2); hold on;
    plot(bins,ig_hist2per(histFailDur),'r','LineWidth',2);
    xlabel('Fixation duration (s)');
    ylabel('% trials');
    title(sprintf('%s %d succ. %d failed trials',runpath,length(idx_succ),length(idx_fail)),'Interpreter','none');
    legend('correct','failed');
end



