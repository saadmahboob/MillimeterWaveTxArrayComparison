% This script provides theoretical value of required power
% The output Pout_adjust gives values in dB.
% It simulates expected signal gain, G, and multiuser inteference, I
% To reach SINR target, we need
% (P * G)/(N + P * I) > TH
% where P is the power adjustment factor (46dBm as reference)
% and N is the AWGN power, i.e., N = 1/SNR_origin.
% Simple steps show as long as G - I * TH > 0, adjusting P gives feasible
% solution for SINR to reach TH
% We use P^{\star} = (N * TH) / (G - I * TH) as required power
% Hardware impirment is not evaluated in this script.

clear;clc;warning off
rng(1); % random seeds
MCtimes = 50; % Monte Carlo times

% ---- System Parameters (SNR and arrays) ------------
M = 1; % number of stream (mmW UE)
case_index = 3; % which use case in the paper
isNLOS = 0;
[SNR_origin,SINR_target] = get_target_SINR(case_index,M);

% Receiver planar antenna dimension
Nr_azim = 4;
Nr_elev = 2;

% Transmitter antenna size range
% Nt_range = [32, 64, 128, 192, 256, 384, 512, 768, 1024];
Nt_range = [64, 128, 192, 256, 384, 512, 768, 1024];
% Nt_range = [32];

% Tx planar antenna dimensions
Nt_azim_range = ones(1,length(Nt_range)) * 32;
Nt_elev_range = Nt_range./Nt_azim_range;

% Make sure scheduled UEs has well seperated LOS paths
ang_grid_num = 32;
ang_grid = linspace(-pi/3,pi/3,ang_grid_num);

% Regularized-ZF coefficient alpha
alpha_range = -30:1:30;

% -------- Channel Statistics Parameters (constant ones) -------------
cluster_num = 3; 
% LOS channel has 3 clusters and with K = 10dB
% NLOS channel has 2 clusters (LOS path has zero gain)

ray_num = 10; % number of rays in a cluster
sigma_delay_spread = 0; % No delay spread in NB model

sigma_AOA_az_spread = 10/180*pi; % 10 deg RMS spread
sigma_AOD_az_spread = 10/180*pi; % 10 deg RMS spread
sigma_AOA_el_spread = 10/180*pi; % 10 deg RMS spread
sigma_AOD_el_spread = 10/180*pi; % 10 deg RMS spread

RacianK = 13; % Ratio between LOS to the rest [dB]

% -------- zero initialization of matrices -------------
gain_sig = zeros(length(Nt_range),length(alpha_range),MCtimes);
gain_MUint = zeros(length(Nt_range),length(alpha_range),MCtimes);

% ------------- Monte Carlo Simulations -------------
for MCindex = 1:MCtimes
    
    clc;fprintf('Monte Carlo Iteration %d/%d\n',MCindex,MCtimes)
    
    % -------- test signal baseband waveform --------
    L = 1e3; % length of test signals
    upsam = 5; % oversampling
    for mm=1:M
        symbols = fix(L*2/upsam);   
        hmod = modem.qammod('M', 16, 'InputType', 'integer');
        hdesign  = fdesign.pulseshaping(upsam,'Square Root Raised Cosine');
        hpulse = design(hdesign);
        data = randi(16,symbols,1)-1;
        data = modulate(hmod, data);
        data = upsample(data,upsam);
        temp_data = conv(data,hpulse.Numerator);
        sig = temp_data(end-L+1-1e3:end-1e3)./sqrt(temp_data(end-L+1-1e3:end-1e3)'...
            *temp_data(end-L+1-1e3:end-1e3)/L);
        sig_length = length(sig);
        sig_pow_dBm = -5;
        R = 50; % was planing to simulate PA nonlinearity; useless now
        sig_pow_V = sqrt(10^(sig_pow_dBm/10)*1e-3*R);
        sig_pow_scale(:,mm) = sig * sig_pow_V;
    end
    
    % -------- Channel parameter statistics (dynamic ones) -------------
    ang_perm = randperm(ang_grid_num); % select LOS angle for UEs
    LOS_cluster_sel = ang_perm(1:M);

    % -------- Chan. Parameter Zero Initialization --------
    ray_gain = zeros(cluster_num*M,ray_num);
    ray_AOD_azim = zeros(cluster_num*M,ray_num);
    ray_AOD_elev = zeros(cluster_num*M,ray_num);
    ray_AOA_azim = zeros(cluster_num*M,ray_num);
    ray_AOA_elev = zeros(cluster_num*M,ray_num);

    % ------- Get mmW Chan. Parameters --------------
    for mm=1:M
        
        print_stat = (mm==1); % print channel statistics
        % printing channel statistic of first UE

        global_cluster_range = (mm-1)*cluster_num+1:mm*cluster_num;
        % indices for clusters that belong to the mm-th user 

        centroid_AOD_az = ang_grid(LOS_cluster_sel(mm));
        % Make sure LOS path is not overlapped

        % Randomly generate chan. parameters
        [ ray_gain(global_cluster_range,:),...
          raydelay,...
          ray_AOA_azim(global_cluster_range,:),...
          ray_AOD_azim(global_cluster_range,:),...
          ray_AOA_elev(global_cluster_range,:),...
          ray_AOD_elev(global_cluster_range,:)] =...
          get_chan_parameter_nogeo(   print_stat,...
                                      cluster_num,...
                                      ray_num,...
                                      sigma_delay_spread,...
                                      sigma_AOA_az_spread,...
                                      centroid_AOD_az,...
                                      sigma_AOD_az_spread,...
                                      sigma_AOA_el_spread,...
                                      sigma_AOD_el_spread,...
                                      isNLOS,...
                                      RacianK);
    end
    
    % -------------  for loop over Tx array size ---------------
    for tt=1:length(Nt_azim_range)
        Nt_azim = Nt_azim_range(tt);
        Nt_elev = Nt_elev_range(tt);
        Nt = Nt_azim * Nt_elev;
        chan_raw = zeros(M, Nt);
        chan = zeros(M, Nt);
        
        % -------------  for loop for each UE (channel generation) ---------------
        for mm=1:M
            % Find range of parameter to generate channel
            temp_range = zeros(cluster_num,1);
            temp_range = (mm-1)*cluster_num+1:mm*cluster_num;

            MIMO_chan = get_H_MIMO_3d(      ray_gain(temp_range,:),...
                                            ray_AOD_azim(temp_range,:),...
                                            ray_AOD_elev(temp_range,:),...
                                            ray_AOA_azim(temp_range,:),...
                                            ray_AOA_elev(temp_range,:),...
                                            cluster_num,...
                                            ray_num,...
                                            Nt_azim,...
                                            Nt_elev,...
                                            Nr_azim,...
                                            Nr_elev);

            % The combining vector at Rx is from SVD and unit-magnitude scaling
            [U_mtx, Sigma_mtx, V_mtx] = svd(MIMO_chan);
            combiner = U_mtx(:,1)./abs(U_mtx(:,1)); 

            % Post combining channel is an MISO channel (a row vector) for each UE
            chan_raw(mm,:) = (combiner' * MIMO_chan)';

            % Normalize channel gain; Because each UE has the same SNR
            chan(mm,:) = chan_raw(mm,:)./norm(chan_raw(mm,:))*sqrt(Nt);
        end
        
        % -------------  for loop (evaluation G and I with sweeping alpha) -------------
        for aa=1:length(alpha_range)
            precoding_mtx = zeros(Nt, M);

            alpha = 10^(alpha_range(aa)/10);
            precoding_mtx = chan'*inv(chan*chan'+eye(M)*alpha*sqrt(Nt));

            % Normalized for unit output power
            array_sig_raw = zeros(Nt,L);
            array_sig = zeros(Nt, L);
            array_sig_raw =  precoding_mtx * sig_pow_scale.';
            array_sig = array_sig_raw./norm(array_sig_raw,'fro')*sqrt(L);

            mm = 1; % Consider only the first UE
            rx_sig = zeros(sig_length, 1);
            rx_sig = (chan(mm,:) * array_sig).';

            %  Normalize the Beamforming Gain (real gain)
            %  ------- min E||sig_org - sig_rx * alpha||^2 -----------
            sig_pow_norm = sig_pow_scale(:,mm)./norm(sig_pow_scale(:,mm))*sqrt(L);
            g_hat = pinv(sig_pow_norm) * rx_sig;
            gain_sig(tt,aa,MCindex) = norm(chan(mm,:) * array_sig)^2/norm(array_sig,'fro')^2;
            gain_MUint(tt,aa,MCindex) = norm(g_hat * sig_pow_norm - rx_sig)^2/L;
        end
    end
end


%% Signal Gain and MU-Interference Evaluation

Int_mean = zeros(M,1);
gain_sig_mean = zeros(M,1);

for tt=1:length(Nt_azim_range)
    for aa=1:length(alpha_range)
        gain_sig_mean(tt,aa) = mean(squeeze(gain_sig(tt,aa,:)));
        Int_mean(tt,aa) = mean(squeeze(gain_MUint(tt,aa,:)));
    end
end

for tt=1:length(Nt_azim_range)
% for tt=1
    sig_gain = 10*log10(gain_sig_mean(tt,:));
    int_gain = 10*log10(Int_mean(tt,:));
    SIR = sig_gain - int_gain;
    index = ((gain_sig_mean(tt,:)-10^(SINR_target/10)*Int_mean(tt,:))>0);
    temp = (10^((SINR_target-SNR_origin)/10))./(gain_sig_mean(tt,index)-10^(SINR_target/10)*Int_mean(tt,index));
    Pout_adjust(tt) = min(10*log10(temp));
end


figure
plot(alpha_range(index),10*log10(temp))

% figure
% plot(alpha_range, 10*log10(gain_sig_mean),'-o','linewidth',2);hold on
% plot(alpha_range, 10*log10(IpN_mean),'--x','linewidth',2);hold on
% grid on
% xlabel('RZF parameter \alpha (dB)')
% ylabel('Power (dB)')
% title('MUint Power')
% legend('Signal Gain','MU Int. Power')
% xlim([-20,30])
% ylim([-40,20])

