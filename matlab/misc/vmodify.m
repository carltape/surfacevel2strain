function [lon,lat,ve,vn,vmag] = vmodify(lon,lat,ve,vn,vmag)
%VMODIFY modify velocity field for plotting in GMT

% kludge for GMT plotting: set near-zero values to <0
veps = 1e-4;
izero = find(vmag < veps);
vmag(izero) = -veps;

% do not plot points that are fixed
warning(sprintf('removing %i/%i points with v < %.3e mm/yr',length(izero),length(lon),veps));
lon(izero) = [];
lat(izero) = [];
ve(izero) = [];
vn(izero) = [];
vmag(izero) = [];
