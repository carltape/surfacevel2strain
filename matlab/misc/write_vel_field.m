function write_vel_field(odir,ftag,lon,lat,ve,vn,vmag)
%
% called by run_platemodel2gps.m

% write plate model vector COMPONENTS and MAGNITUDES to file (mm/yr)
[~,isort] = sort(vmag);
ww = [ftag '_vec.dat'];
ofile = [odir ww];
disp(['writing file ' ww]);
fid = fopen(ofile,'w');
for ii=1:length(lon)
    jj = isort(ii);
    fprintf(fid,'%12.4f%12.4f%12.4f%12.4f%12.4f\n',...
        lon(jj),lat(jj),ve(jj),vn(jj),vmag(jj));   
    %fprintf(fid,'%18.8e%18.8e%18.8e%18.8e%18.8e\n',...
    %    lon(jj),lat(jj),ve(jj),vn(jj),vmag(jj));   
end
fclose(fid);
