%
% sphereinterp.m
% Carl Tape and Pablo Muse, 2011-01-17
%
% This estimates a smooth field on the sphere from discrete points using
% spherical wavelets. This is the 1D version of surfacevel2strain.m,
% 1D being the number of components of the discrete observations.
%
% See surfacevel2strain/USER_INFO/surfacevel2strain_notes.pdf for details,
% including running the example below.
%
% calls get_1D_dataset.m, sphereinterp_grid.m, sphereinterp_est.m
% called by sphereinterp.m
%

clc, clear, close all
format short, format compact

% add path to additional matlab scripts (specify bdir)
user_path;
   
%========================================================
% USER PARAMETERS

iwavelet = 1;   % =1 for estimation; =0 to view data only
iwrite = 1;

ropt  = input(' Type an index corresponding to a region (1=socal): ');
dopt  = input(' Type an index corresponding to a dataset (1=moho): ');

dir_data   = [bdir 'data/examples/'];
dir_output = [bdir 'matlab_output/'];

%====================================================================
% GET DATA SET

[dlon,dlat,d,dsig,ax0,slabel,ulabel] = get_1D_dataset(ropt,dopt,dir_data);

if iwavelet==0, error('view data only'); end

%====================================================================
% ESTIMATE A SMOOTH MOHO MAP USING SPHERICAL WAVELETS

% =1 to use weights, =0 to ignore weights
if isempty(dsig)
    minlampwr = -8; maxlampwr = 2;
else                % weighted
    minlampwr = -3; maxlampwr = 6;
end

switch dopt
    case 1            
        qmin = 2; qmax = 8; % qmax = 8 or 9
        nlam = 40; ilampick = 2;
        ntrsh = 3;
        nx = 50;        % controls density of points in plotting grid
end

lampwr = linspace(minlampwr,maxlampwr,nlam);
lamvec = 10.^lampwr;

qsec = round(mean([qmin qmax]));
qparm = {qmin,qsec,qmax,ntrsh};
rparm = {nlam,ilampick,lamvec};
if exist('polylon','var')
    pparm = {nx,ulabel,polylon,polylat};
else
    pparm = {nx,ulabel};
end

% KEY COMMAND: call sphereinterp_grid.m to get basis functions
[spline_tot] = sphereinterp_grid(dlon,dlat,ax0,qparm);
ndata = length(dlon);
ngrid = length(spline_tot);

% KEY COMMAND: call sphereinterp_est.m to perform least-squares estimation
[dest,dest_plot,destdph_plot,destdth_plot,lam0,dlon_plot,dlat_plot,na,nb] = ...
    sphereinterp_est(spline_tot,dlon,dlat,d,dsig,ax0,rparm,pparm);

disp('  ');
disp(sprintf('Number of observations, ndata = %i',ndata));
disp(sprintf('Number of basis functions, ngrid = %i',ngrid));
disp('For testing purposes, try decreasing one of these:');
disp(sprintf('  qmax = %i, the densest grid for basis functions',qmax));
disp(sprintf('  nx = %i, the grid density for plotting',nx));
disp(sprintf('  ndata = %i, the number of observations (or ax0)',ndata));

% compute magnitude of surface gradient, then convert to a slope in degrees
% note: d is in units of km, so the earth radius must also be in km
th_plot = (90 - dlat_plot)*pi/180;
destG_plot = sqrt( destdth_plot.^2 + (destdph_plot ./ sin(th_plot)).^2 );
destGslope_plot = atan(destG_plot / 6371) * 180/pi;

figure; scatter(dlon_plot,dlat_plot,4^2,destGslope_plot,'filled');
axis(ax0); title('Slope of surface, degrees'); colorbar;

%X = reshape(dlon_plot,na,nb);
%Y = reshape(dlat_plot,na,nb);
%Z = reshape(destGslope_plot,na,nb);
%figure; pcolor(X,Y,Z); shading interp;

%----------------------------------------------------------------
% WRITE FILES

if iwrite==1
    if ~exist(dir_output,'dir'), mkdir(dir_output); end
    
    ftag = sprintf('%s_q%2.2i_q%2.2i_ir%2.2i_id%2.2i',slabel,qmin,qmax,ropt,dopt);
    %flab = [dir_output slabel '_' stqtag{1} '_' sprintf('ic%2.2i_im%2.2i',idata,sub_opt) ];
    flab = [dir_output ftag];
    disp('writing files with tag:'); disp(flab);
    
    nplot = length(dest_plot);
    
    % data and estimated field
    fid = fopen([flab '.dat'],'w');
    %stfmt = '%12.6f%12.6f%10.3f%10.3f%10.3f\n';
    stfmt = '%18.8e%18.8e%18.8e%18.8e%18.8e\n';
    for ii=1:ndata
        fprintf(fid,stfmt,dlon(ii),dlat(ii),d(ii),dest(ii),dsig(ii));
    end
    fclose(fid);

    % estimated field for a regular grid -- includes derivative fields, too
    fid = fopen([flab '_plot.dat'],'w');
    stfmt = '%18.8e%18.8e%18.8e%18.8e%18.8e%18.8e%18.8e\n';
    for ii=1:nplot
        fprintf(fid,stfmt,dlon_plot(ii),dlat_plot(ii),dest_plot(ii),...
            destdph_plot(ii),destdth_plot(ii),destG_plot(ii),destGslope_plot(ii));
    end
    fclose(fid);

    % write bounds to file
    fid = fopen([flab '_bounds.dat'],'w');
    fprintf(fid,'%18.8e%18.8e%18.8e%18.8e\n',ax0(1),ax0(2),ax0(3),ax0(4));
    fclose(fid);
    
    % write regularization parameter to file
    fid = fopen([flab '_lambda.dat'],'w');
    fprintf(fid,'%18.8e\n',lam0);
    fclose(fid);
end

%========================================================
