function ma1_page_thru_trials_simple(runpath, list_successful_only, plot_trials, detect_saccades,detect_saccades_custom_settings)

if nargin < 2,
	list_successful_only = 0;
end

if nargin < 3,
	plot_trials = 0;
end

if nargin < 4,
	detect_saccades = 0;
end

if nargin < 5,
	detect_saccades_custom_settings = '';
end

load(runpath);
disp(runpath);


if plot_trials,
	hf = figure('Name','Plot trial','CurrentChar',' ');
end

for k = 1:length(trial),
	
	
	if (list_successful_only && trial(k).success) || ~list_successful_only
        
        if 1 % align time axis to trial start
            trial(k).states_onset = trial(k).states_onset - trial(k).tSample_from_time_start(1);
            trial(k).tSample_from_time_start = trial(k).tSample_from_time_start - trial(k).tSample_from_time_start(1);
        end
 		
		
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
			drawnow; pause;
			
			if get(gcf,'CurrentChar')=='q',
				% close;
				break;
			end
			clf(hf);
		end
	end
	
end % for each trial



