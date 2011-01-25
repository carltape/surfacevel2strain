%
% surfacevel2strain.m
% Carl Tape and Pablo Muse, 20-Jan-2010
%
% This program takes set of discrete velocity observations on the sphere
% and estimates a continuous field using multi-scale basis functions.
% This was used in
%   Tape, Muse, Simons, Dong, Webb, "Multiscale Estimation of GPS velocity
%   fields," Geophysicsl Journal International, 2009.
%
% With the estimated velocity field also comes the estimated strain-rate
% tensors and rotation-rate tensors.
%
% SEE NOTES:
%     surfacevel2strain/USER_INFO/
%
% calls
%    getspheregrid.m     -- get spherical gridpoints of order qmin to qmax
%    get_gps_dataset     -- load a dataset for analysis
%    platemodel2gps.m    -- returns surface velocity field for a specified plate model
%    spline_vals_mat.m   -- returns spherical spline basis function values
%    spline_thresh_3_pm.m -- spline thresholding function
%    ridge_carl.m        -- regularization for inversion (compares different methods)
%    vel2Lmat.m          -- converts velocity field and gradients to L tensor
%    surfacevel2strain_figs.m   -- 
%    surfacevel2strain_write.m  -- 
%

clc
close all
format short
format compact
warning off

% add path to additional matlab scripts
path(path,[pwd '/util']);
path(path,[pwd '/func']);

ireg  = input(' Type 1 for new inversion or 0 otherwise: ');

if ireg == 1

    clear
    
    %========================================================

    deg = 180/pi;
    earthr = 6371*1e3;      % earth radius (m)

    % plotting parameters
    colors;
    stype = 'cubic';
    npts = 100;              % grid density for regular plotting meshes
    msize = 6^2;            % marker size for circles in scatter plots
    lontick = [-180:60:180];
    lattick = [-90:30:90];
    stks1 = {'vup','vsouth','veast'};
    stks2 = {'U','V','W'};
    stks3 = {'norm-vS','norm-vT'};

    %========================================================
    % USER PARAMETERS

    % ANALYSIS
    istore = 1;         % =1 if using a pre-stored velocity field
    basistype = input(' Type 1 to use spherical wavelets, 2 for spherical splines: ');
    icov = input(' Type 1 to use the DIAGONAL covariance matrix for weighting (0 otherwise): ');
    ndim = input(' Type the number of components of the v-field for the inversion (2 or 3) : ');
    
    % PLOTTING AND WRITING FILES
    ifigs1 = 1;         % =1 if plotting figures (velocity field)
    ifigs2 = 1;         % =1 if plotting figures (strain rate, etc)
    %ifigs_socal = 0;    % =1 if plotting socal GPS figures for paper (socal_gps_figs.m)
    imask  = input(' Type 1 to plot with the mask (0 otherwise) : ');
    iwrite = input(' Type 1 to write output to files for GMT plotting (0 otherwise) : ');

    iplate_model = 3;   % plate model (oneill, nuvel, revel, bird)
    q = 99;             % 99 for non-global gridpoints
    %ifig_extra = 0;     % extra figures

    mod_labs    = {'oneill','nuvel1A_nnr','revel','bird'};  % PLATE MODELS
    smod = mod_labs{iplate_model};
    stq = num2str(sprintf('%2.2i', q));

    % USER: CHANGE THESE
    dir_base    = '/home/carltape/compearth/surfacevel2strain/';
    dir_output  = [dir_base 'matlab_output/'];
    dir_data     = [dir_base 'data/examples/'];
    %dir_data     = [dir_base 'data/gps_data/'];  % carl
    %dir_grids   = [dir_base 'fortran/grids_output/full_grids/'];
    %dir_plates  = '/home/carltape/gmt/plates/';

    %========================================================
    % LOAD DATAPOINTS

    if q ~= 99     % specify order q grid for global grid (NOT multiscale)

        qmin = 4; qmax = qmin;
        ax0 = [-180 180 -90 90];
        [dlon,dlat,~,~,~] = getspheregrid(ax0,qmin,qmax);
        
        % spherical grids generated by getsubgrids.f90
        %ww = ['thph_q' stq];
        %load([dir_grids ww '.dat']); temp = eval(ww);
        %th = temp(:,1); ph = temp(:,2);
        %dlat = 90 - th*deg;
        %dlon = ph*deg;
        %ax1 = [-180 180 -90 90];

    else            % specify arbitrary set of gridpoints
        
        % USER INPUT
        %ropt  = input(' Type an index corresponding to a region (1=us, 2=cal, 3=socal, ..., 8=parkfield, 9=japan): ');
        %dopt  = input(' Type an index corresponding to a v-field dataset (1=REASON, 2=CCMMv1.0, 3=ASIA, 4=japan, etc): ');
        ropt  = input(' Type an index corresponding to a region (1=us, 2=cal, 3=socal, ..., 8=parkfield): ');
        dopt  = input(' Type an index corresponding to a v-field dataset (1=REASON): ');
        sdopt = sprintf('d%2.2i', dopt);
        
        % KEY COMMAND: get the velocity field (and error estimates)
        [dlon,dlat,vu,vs,ve,su,sn,se,ax0,slabel,stref] = ...
            get_gps_dataset(dir_data,ropt,dopt,istore,iplate_model);
        %[dlon,dlat,vu,vs,ve,su,sn,se,ax0,slabel,stref] = ...
        %    get_gps_dataset_carl(dir_data,ropt,dopt,istore,iplate_model);
    end
    
    % modify booleans (see get_gps_dataset.m)
    if any(dopt == [10 11 20 21 30 31 40 41 50 51 60 61 70 71 80 81])
        imask = 0;
        disp('setting imask = 0 for a uniform field');
    end
    if any(dopt == [10 12 20 22 30 32 40 42 50 52 60 62 70 72 80 82])
        icov = 0;
        disp('setting icov = 0 for no uncertainties');
    end
    if any(dopt == [10:29 60:69])
        ndim = 2;
        disp('setting ndim = 2 for 2D data (horizontal components)');
    end
    
    lonmin = ax0(1); lonmax = ax0(2);
    latmin = ax0(3); latmax = ax0(4);
    ndata = length(dlat);
    
    % compute nominal scalelength of the latlon square of observations
    % --> Lscale is the diameter of a circle with area Atot
    Atot = latlon_area(ax0,earthr);
    Lscale = 2*sqrt(Atot/pi);
    
    % load synthetic fault trace, if there is one
    % (see socal_gps_syn.m)
    %idir = [dir_data 'synthetic/'];  % carl
    idir = dir_data;
    if any(dopt == [10:13 30:33 50:53 60:63 70:73])
        gfile = [idir 'gps_gc_' sdopt '.dat'];
        if ~exist(gfile,'file')
            error(['file does not exist: ' gfile]);
        else
            [lon_gc, lat_gc] = textread(gfile,'%f%f');
        end
    end

    figure; hold on;
    quiver(dlon,dlat,ve,-vs,1); axis equal, axis(ax0);
    if exist('lon_gc'), plot(lon_gc,lat_gc,'r','linewidth',2); end
    xlabel(' Latitude'); ylabel(' Longitude');
    orient tall, wysiwyg, fontsize(9)
    
    %========================================================
    % REMOVE ROTATIONAL FIELD, IF DESIRED
    
    iunrotate = input(' Type 1 to remove a uniform rotation, 0 otherwise: ');
    
    if iunrotate==1
        ve0 = ve;
        vs0 = vs;
        [elatlon, ve_ref, vn_ref] = gps2euler(dlon, dlat, earthr, ve0, -vs0, se, sn);
        stE = sprintf(' Euler vector: (lat = %.2f, lon = %.2f, omega = %.2f deg/Myr)',...
            elatlon(1),elatlon(2),elatlon(3));

        ve0 = ve;
        vs0 = vs;
        ve_res = ve - ve_ref;
        vs_res = vs - (-vn_ref);
        ve = ve_res;
        vs = vs_res;
        
        figure; hold on;
        quiver(dlon,dlat,ve,-vs,1); axis equal, axis(ax0);
        if exist('lon_gc'), plot(lon_gc,lat_gc,'r','linewidth',2); end
        title({'Velocity field with rotational field removed:',stE});
        xlabel(' Latitude'); ylabel(' Longitude');
        orient tall, wysiwyg, fontsize(9);
    end
    
    % (horizontal) speed of plates, m/s
    vmag = sqrt(ve.^2 + vs.^2); 
    
    %========================================================
    % PROPERTIES OF THE GRIDS AND THE SPHERICAL WAVELETS

    q0_vec = [0:12]';
    
    % scalelength (in degrees) for each grid (spline_wang_A.m)
    q_scale_deg = [
        63.43494882292201
        31.71747441146100
        15.85873720573050
        7.92936860286525
        3.96468430143263
        1.98234215071631
        0.99117107535816
        0.49558553767908
        0.24779276883954
        0.12389638441977
        0.06194819220988
        0.03097409610494
        0.01548704805247 ];
    
    % angular support of the wavelet of scale 1/2^j in radians,
    % j = 1,...,8
    % The wavelet scale and the grid resolution are related by j = q-1,
    % and q must be greater or equal 2;
    %ang_support = [1.78468; 1.04664; 0.548118; 0.277342; ...
    %    0.139087; 0.0695956; 0.0348043; 0.017403];
    % a tighter criterion for the support: first zero crossing
    ang_support = [82.4415 47.3103 24.7075 12.4999 6.26815 3.13642 ...
        1.56851 0.784289 0.392149 0.196075 ]'/deg;

    % extrapolate a few more scales using the values above (see plot)
    inew = 10:12;
    ang_support(inew+1) = 10.^polyval(polyfit([0:9]',log10(ang_support),1),inew);
    %figure; plot([0:length(ang_support)-1]',log10(ang_support),'.');
    %xlabel(' scale q'); ylabel('log10 [ angular support of scale-q wavelet ]'); grid on;
    
    ang_support_meters = ang_support*earthr;
    qtrsh_cos_dist = cos(ang_support);
    
    disp('Support of the spherical wavelets:');
    disp('   q      deg           km');
    for ix = 1:length(q0_vec)
        disp(sprintf('%4i %10.3f %10.1f',q0_vec(ix),ang_support(ix)*deg,ang_support_meters(ix)/1000));
    end
    disp('  ');
    
    %========================================================
    % LOAD SPHERICAL SPLINE GRIDPOINTS
    % THESE MUST BE GENERATED FIRST IN get_subgrids.f9

    % min number of gridpoints for a particular order
    nmin = 1;
    
    % the lowest allowable grid order of the basis functions is taken to be
    % one whose support is less than twice the length of the length scale
    % of the region of observations
    ia = find(ang_support_meters < 2*Lscale);
    qmin0 = q0_vec(ia(1));
    disp(sprintf('minimum allowable grid order is %i',qmin0));
    disp(sprintf('   %.2e meters (support of q = %i wavelet) < %.2e meters (2*Lscale)',...
    ang_support_meters(qmin0+1),qmin0,2*Lscale));
    qmin = input([' Type min allowable grid order, qmin >= 0 (try ' num2str(qmin0) '): ']);

    % user picks the max allowable grid (finest scale basis functions)
    qmax = input(' Type max allowable grid order, qmax: ');
    
    if basistype == 1
        %Dscale_deg = q_scale_deg(qmax);
        Dscale_deg = q_scale_deg(qmax+1);
    elseif basistype == 2
        Dscale_deg = q_scale_deg(qmax+1);
    else
        error('basistype must be 1 or 2');
    end
    
    [glon,glat,gq,nvec,axmat] = getspheregrid(ax0,qmin,qmax);
    spline_tot0 = [glon glat gq];
    
%     % load the bounds
%     %ww = 'subgrid_bounds';
%     %load([dir ww '.dat']); temp = eval(ww);
%     %ax0 = [temp(1,1) temp(1,2) temp(1,3) temp(1,4)];
%     ax0 = ax1;
% 
%     % load the number of gridpoints in the region for each order grid
%     temp = load([dir 'num_gridpoints.dat']);
%     
%     % threshold the set of gridpoints
%     iqs = find( and( temp(:,1) >= qmin, temp(:,1) <= qmax) );
%     temp = temp(iqs,:);
%     ins = find( temp(:,2) >= nmin );
%     temp = temp(ins,:);
%     qvec = temp(:,1);
%     nvec = temp(:,2);
%     disp('  '); disp('           q          num'); disp([qvec nvec]);
% 
%     % obtain index ranges for each q-level
%     ngrid = sum(nvec);
%     id    = cumsum(nvec)';
%     %ifr   = [1 id(1:end-1)+1 1; id ngrid]';
%     ifr   = [1 id(1:end-1)+1; id]';
% 
%     numq = length(qvec);
%     spline_tot0 = zeros(ngrid,3);
%     
%     figure; hold on;
%     disp('  '); disp(' load the gridpoints in this region');
%     for iq = 1:numq
%         q = qvec(iq); n = nvec(iq);
%         stit = [' q = ' num2str(q) ' : num = ' num2str(n)]; disp(stit);
% 
%         ww = ['thph_q' num2str(sprintf('%2.2i',q))];
%         load([dir ww '.dat']); temp = eval(ww);
%         lon = temp(:,2)*deg; lat = (pi/2-temp(:,1))*deg;
%         plot(lon,lat,'k.');
% 
%         % fill a matrix with gridpoints
%         inds = [ifr(iq,1) : ifr(iq,2)];
%         spline_tot0(inds,:) = [lon lat q*ones(nvec(iq),1) ];
%     end
%     axis equal, axis(ax0);
    
    %========================================================
    % THRESHOLD INITIAL SET OF BASIS FUNCTIONS

    disp('  '); disp(' threshold the gridpoints');
    if basistype == 1
        % take only gridpoints inside the box
        %ikeep0 = getsubset(spline_tot0(:,1),spline_tot0(:,2),ax0);
        %spline_tot0 = spline_tot0(ikeep0,:);
        
        % threshold wavelets based on data
        ntrsh = 3;       % KEY: number of evaluations >= qtrsh
        %ntrsh = 0;

        [ikeep, inum] = wavelet_thresh(spline_tot0, qtrsh_cos_dist, ...
            ntrsh, dlon, dlat);
        
    elseif basistype == 2
        % threshold spline based on data
        qtrsh = 0.05;    % evaluations must be >= qtrsh
        ntrsh = 3;       % number of evaluations >= qtrsh
        [ikeep, inum] = spline_thresh_3(spline_tot0, qtrsh, ntrsh, ...
            dlon, dlat, {0});
    end

    spline_tot = spline_tot0(ikeep,:);

    ngrid = length(spline_tot);
    if ngrid==0, error('ngrid = 0: check datapoints and gridpoints'); end
    glon = spline_tot(:,1);
    glat = spline_tot(:,2);
    gq = spline_tot(:,3);

    % recompute qvec, nvec, ifr
    jj = 0;
    %nvec = zeros(qmax+1,1);
    nvec = []; qvec = [];
    for q = 0:qmax      % ALL possible q orders
        n = length( find( gq == q ) );
        if n >= 1
            jj = jj+1; qvec(jj) = q; nvec(jj) = n;
            qmax0 = q;
        end
    end

    % if there are no allowable splines in for qmax, then adjust qmax
    qmax = qmax0;
    qvec = qvec(:); nvec = nvec(:);
    numq  = length(qvec);

    id    = cumsum(nvec);
    ifr   = [ [1 ; id(1:end-1)+1] id];
    %inz = find(nvec==0); ifr(inz,:) = 0;
    disp('  '); disp('     q   num    id    i1    i2'); disp([qvec nvec id ifr]);

    % inds for the highest q-level
    inds_qmax = [ifr(end,1) : ifr(end,2)];
    %iz = min(inz)-1;
    %inds_qmax = [ifr(iz,1) : ifr(iz,2)];

    % select the multiscale decomposition based on what you designate to be the
    % 'secular field' associated with the plate convergence
    % KEY : qvec --> iqvec, ifr --> iqr
    % NOTE: the first row (iqvec, iqr) constitutes ALL available splines
    %qsec = 5;
    qsec  = input([' Enter max q grid for secular field (' ...
        num2str(qmin) ' <= qsec <= ' num2str(qmax) '): ']);
    iqsec = find(qvec == qsec);
    irecs = find(qvec > qsec);
    iqvec = [qvec(1) qvec(end) ; qvec(1) qvec(iqsec) ; [qvec(irecs) qvec(irecs)]];
    nump = length(iqvec);
    iqr = [1 ifr(end,2) ; 1 ifr(iqsec,2) ; ifr(iqsec+1:end,:)];
    ipran = [qsec ; qvec(irecs)];

    if basistype == 1
        stqran = ['q = ' num2str(qvec(1)) ' to ' num2str(qvec(end)) ' (' num2str(ngrid) ')'];
        strsh1 = [num2str(ngrid) ' wavelets / ' num2str(length(spline_tot0)) ' total'];
        strsh2 = [' with >= ' num2str(ntrsh) ' stations inside their corresponding spatial supports'];
    end  
    if basistype == 2
        stqran = ['q = ' num2str(qvec(1)) ' to ' num2str(qvec(end)) ' (' num2str(ngrid) ')'];
        strsh1 = [num2str(ngrid) ' splines / ' num2str(length(spline_tot0)) ' total'];
        strsh2 = [' with >= ' num2str(ntrsh) ' values that are > ' num2str(sprintf('%0.2f', qtrsh))];
    end
    disp('  '); disp(['Thresholding GRIDPOINTS '  stqran ':']); disp([strsh1 strsh2]); disp('  ');

    nvec = zeros(nump,1);
    for ip = 1:nump
        q1 = iqvec(ip,1); q2 = iqvec(ip,2);
        if1 = iqr(ip,1);  if2 = iqr(ip,2);
        if if1+if2 > 0, nvec(ip) = if2-if1+1; end
        stqtag{ip} = sprintf('q%2.2i_q%2.2i',q1,q2);
        stqs{ip} = [' q = ' num2str(q1) ' to ' num2str(q2)];
        stis{ip} = [' j = ' num2str(if1) ' to ' num2str(if2) ' (' num2str(nvec(ip)) ')'];
        stit = [stqs{ip} ',' stis{ip}]; disp(stit);
    end
    
     % indexing for multi-scale strain and multi-scale residual field
    id2 = cumsum(nvec(2:end));
    iqr2 = [ ones(nump-1,1) id2];
    iqvec2 = [qvec(1)*ones(length(ipran),1) ipran];
    %iqvec2 = [qvec(1) qvec(iqsec) ; [qvec(1)*ones(length(irecs),1) qvec(irecs)]];

    % plot ALL spline gridpoints
    figure; hold on;
    scatter(glon,glat,4^2,gq,'filled');
    %scatter(glon,glat,msize,'ko');
    colorbar('ytick',qvec);
    %plot(glon,glat,'.');
    %plot(ax1([1 2 2 1 1]), ax1([3 3 4 4 3]), 'k');
    plot(ax0([1 2 2 1 1]), ax0([3 3 4 4 3]), 'k');
    axis equal, axis tight;
    title({[slabel ' :  ' stqran],[strsh1 strsh2]},'interpreter','none');
    xlabel(' Latitude'); ylabel(' Longitude');
    orient tall, wysiwyg, fontsize(10)

    % plot spline gridpoints by order q
    figure; nc=2; nr=ceil(nump/nc);
    if numq==1, clims = [0 qmax]; else clims = [qvec(1) qvec(end)]; end
    for ip = 1:nump
        inds = [iqr(ip,1) : iqr(ip,2)];
        subplot(nr,nc,ip); hold on;
        plot(dlon,dlat,'k+');
        if sum(inds) > 0
            %plot(glon(inds),glat(inds),'.');
            scatter(glon(inds),glat(inds),4^2,gq(inds),'filled');
        end
        caxis(clims); colorbar('ytick',qvec);
        axis equal
        axis(ax0);
        %axis(ax1);
        title({stqs{ip}, stis{ip}});
    end
    orient tall, wysiwyg, fontsize(9)

    % figure; nc=2; nr = ceil(numq/nc);
    % for iq=1:numq
    %     q = qvec(iq);
    %     inds = [ifr(iq,1) : ifr(iq,2)];
    %     subplot(nr,nc,iq); hold on;
    %     plot(dlon,dlat,'r+');
    %     plot(glon(inds),glat(inds),'.');
    %     axis equal, axis(ax0);
    %     title(stnq{iq});
    % end
    % fontsize(8), orient tall, wysiwyg
    
    %========================================================
    % DAMPED LSQ TO ESTIMATE THE VELOCITY FIELD

    % REGULARIZATION MATRIX (MODEL COVARIANCE MATRIX)
    % diagonal of regularization matrix (or model covariance matrix)
    scales = spline_tot(:,3);   % CHT 8/3/08, changed from spline_tot(:,3)-1
    pow2scales = 2.^scales;                 % is it 2^p or 4^p ?
    Dmat = diag(pow2scales.^2);
    Dhalfinv = diag(1 ./ pow2scales );      % regularization by gradient-model norm
    %Dhalfinv = eye(ngrid);                  % regularization by model-norm
    
    %--------------------------------------------------------
    % CONSTRUCT DESIGN MATRIX for components of velocity field

    %ispheroidal = input(' Type 1 to use spheroidal-toroidal basis functions (0 otherwise): ');
    ispheroidal = 0;
    
    disp('  '); disp('Constructing the design matrix...');

    % get the 'base' design matrix
    if basistype == 1
        if ispheroidal==0
            [G, Gdph, Gdth] = dogsph_vals_mat(spline_tot, dlon, dlat, {3});
        else
            [G, Gdph, Gdth, Gdphdph, Gdthdth, Gdthdph] = ...
                dogsph_vals_mat(spline_tot, dlon, dlat, {6});
        end
    end
    if basistype == 2
        [G, Gdph, Gdth] = spline_vals_mat(spline_tot, dlon, dlat);
        %[G, Gdph, Gdth] = spline_vals_mat(spline_tot, dlon, dlat, ndim);
    end

    %-------------------------------
    % CONSTRUCT DESIGN MATRIX for spheroidal-toroidal components
    
    % number of regularization parameters
    if ispheroidal == 1
        nreg = 2; stps = stks2;
    else
        nreg = 3; stps = stks1;
    end
    lam0 = NaN * ones(1,nreg);       % NOTE: lam0(1) = NaN if ndim = 2
    
    if ispheroidal == 1
        % design matrix containing both horizontal components
        sinth = sin( (90 - dlat)/deg );
        iGdph = repmat(1./sinth,1,ngrid) .* Gdph;
        Gmode = [ Gdth iGdph ; 
                  iGdph -Gdth ];
        
        % matrices for computing u_V (spheroidal) and u_W (toroidal)
        %Vmode = [ Gdth ; iGdph ];
        %Wmode = [ iGdph ; -Gdth];
              
        dmode = [vs ; ve];

        Wvec = [ 1 ./ sn.^2 ; 1 ./ se.^2 ];
        Whalf = diag( sqrt(Wvec) );

        Dmat_mode = zeros(2*ngrid,2*ngrid);
        Dmat_mode(1:ngrid,1:ngrid) = Dmat;
        Dmat_mode(ngrid+1:2*ngrid,ngrid+1:2*ngrid) = Dmat;

        Dhalfinv_mode = zeros(2*ngrid,2*ngrid);
        Dhalfinv_mode(1:ngrid,1:ngrid) = Dhalfinv;
        Dhalfinv_mode(ngrid+1:2*ngrid,ngrid+1:2*ngrid) = Dhalfinv;

        numlam = 40;
        minlampwr = 1; maxlampwr = 8;
        lampwr = linspace(minlampwr,maxlampwr,numlam);
        lamvec = 10.^lampwr;

        [f_h_prime, rss, mss, Gvec, Fvec, dof, kap, iL, iGCV, iOCV] = ...
            ridge_carl(Whalf*dmode, Whalf*Gmode*Dhalfinv_mode, lamvec);

        % KEY: select regularization parameter
        disp(sprintf('L-curve lambda = %.3e (index %i)',lamvec(iL),iL));
        disp(sprintf('    OCV lambda = %.3e (index %i)',lamvec(iOCV),iOCV));
        disp(sprintf('    GCV lambda = %.3e (index %i)',lamvec(iGCV),iGCV));
        ilam = input(sprintf('Type an index for lambda (try iOCV = %i): ',iOCV));
        lam = lamvec(ilam);
        lam0(end) = lam;

        fmode = inv(Gmode'*diag(Wvec)*Gmode + lam^2*Dmat_mode)*Gmode'*diag(Wvec)*dmode;

        dmode_est = Gmode*fmode;
        vs_est = dmode_est(1:ndata);
        ve_est = dmode_est(ndata+1:2*ndata);
    end

    %-------------------------------
    
%     % construct design matrix by stacking base design matrices
%     G = zeros(ndata*ndim,ngrid*ndim);
%        G(1:ndata, 1:ngrid) = A;
%     Gdph(1:ndata, 1:ngrid) = Adph;
%     Gdth(1:ndata, 1:ngrid) = Adth;
%     if ndim==2
%            G(  ndata+1:2*ndata,   ngrid+1:2*ngrid) = A;
%         Gdph(  ndata+1:2*ndata,   ngrid+1:2*ngrid) = Adph;
%         Gdth(  ndata+1:2*ndata,   ngrid+1:2*ngrid) = Adth;
% 
%     elseif ndim==3
%            G(  ndata+1:2*ndata,   ngrid+1:2*ngrid) = A;
%         Gdph(  ndata+1:2*ndata,   ngrid+1:2*ngrid) = Adph;
%         Gdth(  ndata+1:2*ndata,   ngrid+1:2*ngrid) = Adth;
%            G(2*ndata+1:3*ndata, 2*ngrid+1:3*ngrid) = A;
%         Gdph(2*ndata+1:3*ndata, 2*ngrid+1:3*ngrid) = Adph;
%         Gdth(2*ndata+1:3*ndata, 2*ngrid+1:3*ngrid) = Adth;
%     end
%     
%     % INDEXING for composite data vector and model vector
%     iorder = 1;         % how to order the datapoints in the design matrix
%     opts_index{1} = iorder;
%     if ndim==2
%         [isouth_i, ieast_i] = subindexing(ndata,ndim,opts_index);
%         [isouth_j, ieast_j] = subindexing(ngrid,ndim,opts_index);
%     elseif ndim==3
%         [iup_i, isouth_i, ieast_i] = subindexing(ndata,ndim,opts_index);
%         [iup_j, isouth_j, ieast_j] = subindexing(ngrid,ndim,opts_index);
%     end

    %========================================================
    % CONSTRUCT WEIGHTING MATRIX FOR INVERSION
    % order is r-theta-phi (up-south-east)
    %
    % NOTE: WE HAVE ALREADY CONVERTED THE STANDARD ERRORS TO M/YR
    %
    % standard error = sqrt( variance ) (p. 27)
    % variance = (standard error)^2

%     Wvec = ones(ndata*ndim,1);      % icov = 0 (no weighting)
%     if icov==1
% 
%         % compute covariance matrix DIAGONAL
%         % see Weisberg (2005), p. 96+
%         % When wi is LARGE, the observation has LOW variance and HIGH weight
%         if ndim==3
%             sigma_vec = [su ; sn ; se];
%         else
%             sigma_vec = [sn ; se];
%         end
%         Wvec = 1 ./ sigma_vec.^2;
%     end
% 
%     % composite data vector
%     d = zeros(ndata*ndim,1);
%     if ndim==1
%         d = ve;     % original version
% 
%     elseif ndim==2
%         d(isouth_i) = vs;
%         d(ieast_i)  = ve;
% 
%     elseif ndim==3
%         d(iup_i)    = vu;
%         d(isouth_i) = vs;
%         d(ieast_i)  = ve;
%     end

    %===========================================
    
    % in many cases, you MUST have a non-zero damping parameter
    numlam = 40;
    %numlam = 20;

    if icov==0          % unweighted
        minlampwr = -8; maxlampwr = 2;
    else                % weighted
        minlampwr = -3; maxlampwr = 6;
        %minlampwr = 1; maxlampwr = 8;    % GJI figure
    end
    lampwr = linspace(minlampwr,maxlampwr,numlam);
    lamvec = 10.^lampwr;

    stlams = [' lam = ' num2str(sprintf('%.2f',lamvec(1)))  ...
        ' to ' num2str(sprintf('%.2f',lamvec(end))) '  (' num2str(numlam) ' solutions)'];
    
    % Loop over each COMPONENT of the velocity field; this means that each
    % component may have a different regularization parameter.
    
    if ispheroidal==1
        kmin = 3;
        if ndim==3, kmax = 3; else kmax = 0; end
    else
        kmax = 3;
        if ndim==3, kmin = 1; else kmin = 2; end
    end
        
    for kk = kmin:kmax
        
        % data vector and weighting vector (looping order is r-theta-phi)
        % DATA COVARIANCE MATRIX
        switch kk
            case 1, d = vu; wu = 1 ./ su.^2; Wvec = wu;
            case 2, d = vs; ws = 1 ./ sn.^2; Wvec = ws;
            case 3, d = ve; we = 1 ./ se.^2; Wvec = we;
        end

        if icov == 0
            wu = ones(ndata,1);
            ws = ones(ndata,1);
            we = ones(ndata,1);
            Wvec = ones(ndata,1);
        end
        
        disp(['regularization curves for scalar field ' stps{kk}]);
        trms = zeros(numlam,1);
        mss = zeros(numlam,1);

        % KEY: choose parameter selection technique
        % CASE 1 is preferred, since it compares several techniques
        % CASE 5 uses a previously saved value.
        imethod = 1;

        Gvec = zeros(numlam,1);
        rss0 = 0; mss0 = 0; G0 = 0;

        switch imethod
            case 1
                Whalf = diag( sqrt(Wvec) );     % Weisberg, p. 97
               
                [f_h_prime, rss, mss, Gvec, Fvec, dof, kap, iL, iGCV, iOCV] = ...
                 	ridge_carl(Whalf*d, Whalf*G*Dhalfinv, lamvec);
                
                % (un-)transform model vector
                f_h = zeros(ngrid,numlam);
                for ik = 1:numlam
                    f_h(:,ik) = Dhalfinv * f_h_prime(:,ik);
                end
                
                %if basistype == 2
                %    [f_h, rss, mss, Gvec, Fvec, dof, kap, iL, iGCV, iOCV] = ...
                %        ridge_carl(Whalf*d, Whalf*G, lamvec);
                %end
                %if basistype == 1
                %    [f_h, rss, mss, Gvec, Fvec, dof, kap, iL, iGCV, iOCV] = ...
                %        ridge_carl_pm_old(Whalf*d, Whalf*G, lamvec, ndim, spline_tot(:,3)-1);
                %end

            case 2
                % NOTE: THIS IS NOT AN EFFICIENT ALGORITHM (see ridge_carl.m instead)
                for ii=1:numlam
                    if mod(ii,round(numlam/10))==0, disp([num2str(ii) '/' num2str(numlam)]); end
                    lam = lamvec(ii);                           % damping
                    m = inv(G'*G + lam^2*eye(ngrid*ndim))*G'*d; % Menke 3.32 (p. 52)
                    res  = G*m - d;                             % residuals

                    rss(ii) = sum(res.^2);     % FIT: identical to rss from tsvd.m
                    mss(ii) = sum(m.^2);       % MODEL NORM: identical to f_r_ss from tsvd.m
                end

            case 3

                % number of simulations to sub-sample the full data
                NMC = 2000;

                % fraction of the data to use for each sub-sample set
                %Fmin = 0.1; Fmax = 0.9; Finc = 0.1;
                %Fmin = 0.5; Fmax = 0.5; Finc = 0.1;
                Fmin = 0.999; Fmax = Fmin; Finc = 1;
                Fvec = [Fmin:Finc:Fmax];
                numF = length(Fvec);

                % generalized cross-validation (brute force method)
                rss_mat = gcv_carl(d, G, lamvec, NMC, Fvec);

                % initialize matrices
                fit_mean = zeros(numlam,numF);
                fit_bot = zeros(numlam,numF);
                fit_top = zeros(numlam,numF);
                lam_min = zeros(numF,1);
                rss_min = zeros(numF,1);
                for jj=1:numF
                    x = log10(lamvec);

                    rss = log10(rss_mat(:,:,jj));     % LOG transformation
                    rss_mean = mean(rss');            % mean for each lambda
                    rss_std  = std(rss');             % std for each lambda

                    % fit a polynomial to curves: means, means+std, means-std
                    Pmax = 4;
                    P0 = polyfit(x,rss_mean,Pmax); yfit = polyval(P0,x);
                    P = polyfit(x,rss_mean-rss_std,Pmax); yfitbot = polyval(P,x);
                    P = polyfit(x,rss_mean+rss_std,Pmax); yfittop = polyval(P,x);

                    % find minimum of polynomial numerically
                    xsmooth = log10(linspace(lamvec(1),lamvec(end),1000));
                    ysmooth = polyval(P0,xsmooth);
                    [ymin,imin] = min(ysmooth);
                    lam_min(jj) = 10^xsmooth(imin);
                    rss_min(jj) = 10^ysmooth(imin);
                    lplot = log10(lam_min(jj));

                    % save fitting curves into matrices
                    fit_mean(:,jj) = yfit';
                    fit_bot(:,jj) = yfitbot';
                    fit_top(:,jj) = yfittop';
                end

                % save output
                %save('gcv_data_03','rss_mat','lamvec','NMC','Fvec','rss','rss_mean','rss_std','fit_mean','fit_bot','fit_top','lam_min','rss_min');

            case 4
                % ordinary cross-validation (brute force method)
                rss_vec = ocv_carl(d, G, lamvec);

                % find numerical minimum
                %inds = [23:31];
                inds = [23:31];
                x = log10(lamvec(inds)');
                y = log10(rss_vec(inds));
                Pmax = 4;
                P0 = polyfit(x,y,Pmax); yfit = polyval(P0,x);
                xsmooth = log10(linspace(lamvec(inds(1)),lamvec(inds(end)),1000));
                ysmooth = polyval(P0,xsmooth);
                [ymin,imin] = min(ysmooth);
                lam_min = 10^xsmooth(imin);
                rss_min = 10^ysmooth(imin);

                figure; hold on; grid on;
                plot(log10(lamvec),log10(rss_vec),'b.');
                plot(xsmooth,ysmooth,'r');
                plot(log10(lam_min),log10(rss_min),'r.','markersize',24)
                xlabel(' Regularization parameter, log10 (\lambda)'); ylabel(' OCV function, log(G)');
                title([' lam = ' num2str(sprintf('%.4f',lam_min))]);

                % save output
                %save('ocv_data_01','rss_vec','lamvec','lam_min','rss_min','xsmooth','ysmooth');

        end  % for kk

        % KEY: select regularization parameter
        disp(sprintf('L-curve lambda = %.3e (index %i)',lamvec(iL),iL));
        disp(sprintf('    OCV lambda = %.3e (index %i)',lamvec(iOCV),iOCV));
        disp(sprintf('    GCV lambda = %.3e (index %i)',lamvec(iGCV),iGCV));
        ilam = input(sprintf('Type an index for lambda (try iOCV = %i): ',iOCV));
        lam0(kk) = lamvec(ilam);
        
%         % KEY: select on the basis of the OCV curve, GCV curve, or L curve
%         lam0(kk) = lamvec(iOCV);
%         %lam0(kk) = lamvec(iGCV);
%         if ropt==10, lam0(kk) = lamvec(iL); end         % wedge field q=0-3
%         if and(kk==1,dopt==1), lam0(kk) = 100; end         % vertical reason field
        
    end

    disp('  ');
    disp(' got the regularization parameters (vr, vth, vphi):');
    disp(['    lam0 = ' sprintf('%.2e %.2e %.2e',lam0) ]);
    break

    %========================================================
end  % ireg
%========================================================

if ~exist('lam0','var'), error('must run inversion first'); end
disp('  '); disp(' computing the model vector...');

%--------------------------------
% COMPUTE MODEL VECTOR

if ispheroidal == 1
    fU = zeros(ngrid,1);
    fV = zeros(ngrid,1);
    fW = zeros(ngrid,1);
    
    lam = lam0(end);        % horizontal
    fmode = inv(Gmode'*diag(Wvec)*Gmode + lam^2*Dmat_mode)*Gmode'*diag(Wvec)*dmode;
    fV = fmode(1:ngrid);
    fW = fmode(ngrid+1:2*ngrid);
    dmode_est = Gmode*fmode;
    vs_est = dmode_est(1:ndata);
    ve_est = dmode_est(ndata+1:2*ndata);
    
    %vSr = G*fU;    % vertical component
    vSr = zeros(ndata,1);
    vSs = Gdth*fV;
    vSe = iGdph*fV;
    vTs = iGdph*fW;
    vTe = -Gdth*fW;
    norm_vS = sqrt( vSr.^2 + vSs.^2 + vSe.^2 );
    norm_vT = sqrt( vTs.^2 + vTe.^2 );      % no vertical component

else
    fu = zeros(ngrid,1);
    fs = zeros(ngrid,1);
    fe = zeros(ngrid,1);
    
    % regularization parameters
    lam_u = lam0(1);
    lam_s = lam0(2); 
    lam_e = lam0(3);
    %if dopt == 1     % socal REASON dataset
    %    lam_u = mean([lam_s lam_e]);   % in general, this will give LESS damping
    %    lam_u = 100;     % LOW DAMPING
    %end

    % estimated posterior model covariance matrix and mean model vector
    Cm_s = inv(G'*diag(ws)*G + lam_s^2*Dmat);   % m x m
    Cm_e = inv(G'*diag(we)*G + lam_e^2*Dmat);   % m x m
    fs = Cm_s*G'*diag(ws)*vs;                   % m x 1
    fe = Cm_e*G'*diag(we)*ve;                   % m x 1
    if ndim==3
        Cm_u = inv(G'*diag(wu)*G + lam_u^2*Dmat);
        fu = Cm_u*G'*diag(wu)*vu;
    end

    if 0==1
        for kk = 1:numlam
           lam = lamvec(kk);
           fu = inv(G'*diag(wu)*G + lam^2*Dmat)*G'*diag(wu)*vu;
           vu_est = G*fu;
           vu_res = vu - vu_est;
           ve_med(kk) = median(abs(1e3*vu_res));
        end
        figure; semilogx(lamvec,ve_med,'.'); grid on;
        xlabel('lambda'); ylabel('median(abs(vu-res))');
    end
    
    %fs = f(isouth_j);
    %fe = f(ieast_j);

    %v_est = G*f;
    %v_res = d - v_est;

    % BASE design matrix
    % (This block is repeated three times to make G.)
    %G0 = G(ieast_i,ieast_j);

    % estimated values at the observation points
    vs_est = G*fs;      % n x 1
    ve_est = G*fe;      % n x 1
    
    % estimated posterior data covariance matrix -- DIAGONAL ONLY
    Cd_s_diag = diag(G*Cm_s*G');        % n x 1
    Cd_e_diag = diag(G*Cm_e*G');        % n x 1
    sn_post = sqrt(Cd_s_diag);          % n x 1
    se_post = sqrt(Cd_e_diag);          % n x 1
end

%--------------------------------
% BASIC SET OF FIGURES

iplot_qcen = 0;   % plot gridpoints at centers of basis functions
iplot_fault = 1;  % plot fault

[lonsaf,latsaf,xsay,ysaf] = textread([dir_base 'gmt/input/safdata.dat'],'%f%f%f%f');
%load('safdata');

% plot either the synthetic fault (great circle) or a different boundary
if exist('lon_gc','var')
    lonseg = lon_gc;
    latseg = lat_gc;
else
    lonseg = lonsaf;
    latseg = latsaf;
end

%------------------

if ispheroidal == 1
   fall = [fU fV fW];
else
   fall = [fu fs fe];
end

% power in each scale
Pq = zeros(numq,3);
Pp = zeros(nump-1,3);
if basistype==1
    % compute power in each scale (wavelets)
    for jj=1:3
        for iq = 1:numq
            inds = [ifr(iq,1) : ifr(iq,2)];
            Pq(iq,jj) = sum( fall(inds,jj).^2 );
        end
    end

    % same as above, only putting all the "secular field" power together
    for jj=1:3
        for ip = 2:nump
            inds = [iqr(ip,1) : iqr(ip,2)];
            Pp(ip-1,jj) = sum( fall(inds,jj).^2 );
        end
    end
    
else
    disp('computation of power is only implemented for wavelets');
end

% plot lines by scale
fmax = 1.1*max(abs(fall(:)));
[xmat,ymat] = vertlines([1 ; id],-fmax,fmax);

figure; nr=3; nc=1;
subplot(nr,nc,1);
plot([1:ngrid],fall(:,1),'k.',[1:ngrid],fall(:,2),'b.',[1:ngrid],fall(:,3),'r.',xmat,ymat,'k');
axis([0 ngrid -fmax fmax]); grid on;
xlabel('k, index of frame function'); ylabel('f_k, coefficient');
subplot(nr,nc,2); 
semilogx([1:ngrid],fall(:,1),'k.',[1:ngrid],fall(:,2),'b.',[1:ngrid],fall(:,3),'r.',xmat,ymat,'k');
axis([0.9 ngrid -fmax fmax]); grid on;
xlabel('k, index of frame function'); ylabel('f_k, coefficient');
subplot(nr,nc,3);
semilogy(qvec,Pq(:,1),'k.-',qvec,Pq(:,2),'b.-',qvec,Pq(:,3),'r.-','markersize',18); grid on;
legend(stps); xlabel('scale'); xlim([-1 qmax+1]); ylabel('Power = sum ( f_k^2 )');
orient tall, wysiwyg, fontsize(9)

% plot lines by scale
[xmat,ymat] = vertlines([1 ; iqr(2:end,2)],-fmax,fmax);

figure; nr=3; nc=1;
subplot(nr,nc,1);
plot([1:ngrid],fall(:,1),'k.',[1:ngrid],fall(:,2),'b.',[1:ngrid],fall(:,3),'r.',xmat,ymat,'k');
axis([0 ngrid -fmax fmax]); grid on;
xlabel('k, index of frame function'); ylabel('f_k, coefficient');
subplot(nr,nc,2); 
semilogx([1:ngrid],fall(:,1),'k.',[1:ngrid],fall(:,2),'b.',[1:ngrid],fall(:,3),'r.',xmat,ymat,'k');
axis([0.9 ngrid -fmax fmax]); grid on;
xlabel('k, index of frame function'); ylabel('f_k, coefficient');
subplot(nr,nc,3);
semilogy(ipran,Pp(:,1),'k.-',ipran,Pp(:,2),'b.-',ipran,Pp(:,3),'r.-','markersize',18); grid on;
set(gca,'xtick',ipran','xticklabel',stqtag(2:end));
legend(stps); xlabel('scale'); xlim([qsec-0.5 qmax+0.5]); ylabel('Power = sum ( f_k^2 )');
orient tall, wysiwyg, fontsize(9)

%---------------------

% residuals for horizontal components
vs_res = vs - vs_est;
ve_res = ve - ve_est;

% magnitude of surface vector
vmag_est = sqrt(ve_est.^2 + vs_est.^2);
vmag_res = vmag - vmag_est;

if ndim==3
    %fu = f(iup_j);
    
    % least squares solution
    Cm_u = inv(G'*diag(wu)*G + lam_u^2*Dmat);   % m x m
    fu = Cm_u*G'*diag(wu)*vu;                   % m x 1
    vu_est = G*fu;                              % n x 1
    vu_res = vu - vu_est;                       % n x 1
    Cd_u_diag = diag(G*Cm_u*G');                % n x 1
    su_post = sqrt(Cd_u_diag);                  % n x 1

    figure; nr=3; nc=1;
    vumax = max(abs(1e3*vu));
    resmax = max(abs(1e3*vu_res));
    
    subplot(nr,nc,1); hold on;
    plot( 1e3*vu, 1e3*vu_est, '.');
    plot(vumax*[-1 1],vumax*[-1 1],'r--');
    xlabel('OBSERVED  v_r (mm/yr)');
    ylabel('ESTIMATED  v_r (mm/yr)');
    %title(['cor(vu-obs, vu-est) = 'num2str(corr(vu,vu_est))]);  %
    %STATISTICS TOOLBOX -- corr
    axis equal, grid on;

    subplot(nr,nc,2); hold on;
    plot(1e3*vu_res, '.');
    xlabel('Observation number ');
    ylabel('RESIDUALS  v_r (mm/yr)');
    %title(['mean(abs(res)) = ' num2str(mean(abs(1e3*vu_res))) ' mm/yr']);
    title(['median(abs(res)) = ' num2str(median(abs(1e3*vu_res))) ' mm/yr']);
    grid on;

    edges = linspace(-resmax,resmax,15);
    subplot(nr,nc,3); plot_histo(1e3*vu_res,edges);
    xlabel('RESIDUALS  v_r (mm/yr)');
    %edges = [-30:2:30]; [N,bin] = histc(1e3*vu_res,edges);
    %subplot(nr,nc,4), bar(edges,N,'histc'); xlim([min(edges) max(edges)]);
    %grid on;
    %xlabel('RESIDUALS  v_r (mm/yr)'); ylabel('number');
    
    orient tall, wysiwyg, fontsize(9)
    
    figure; nr=3; nc=1;
    
    subplot(nr,nc,1); hold on;
    scatter(dlon,dlat,msize,1e3*vu,'filled');
    if iplot_fault==1, plot(lonseg,latseg,'k'); end
    axis equal, axis(ax0), grid on;
    caxis([-1 1]*0.2*vumax); colorbar;
    %xlabel('Longitude'); ylabel('Latitude');
    title('OBSERVED  v_r (mm/yr)');
    
    subplot(nr,nc,2); hold on;
    scatter(dlon,dlat,msize,1e3*vu_est,'filled');
    if iplot_fault==1, plot(lonseg,latseg,'k'); end
    axis equal, axis(ax0), grid on;
    caxis([-1 1]*0.2*vumax); colorbar;
    %xlabel('Longitude'); ylabel('Latitude');
    title('ESTIMATED  v_r (mm/yr)');
    
    subplot(nr,nc,3); hold on;
    scatter(dlon,dlat,msize,1e3*vu_res,'filled');
    if iplot_fault==1, plot(lonseg,latseg,'k'); end
    axis equal, axis(ax0), grid on;
    caxis([-1 1]*0.5*resmax); colorbar;
    %xlabel('Longitude'); ylabel('Latitude');
    title('RESIDUALS  v_r (mm/yr)');
    
    orient tall, wysiwyg, fontsize(9)
end

%========================================================
% FIGURES: velocity field estimates

surfacevel2strain_figs;

%========================================================
% WRITE DATA TO FILE FOR GMT PLOTTING

if iwrite == 1
    surfacevel2strain_write;
end

disp('DONE with surfacevel2strain.m');

%========================================================
