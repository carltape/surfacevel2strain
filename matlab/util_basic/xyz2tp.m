function [th,ph,rho] = xyz2tp(xyz)
%XYZ2TP convert from (x,y,z) to theta, phi
%
% This function takes a matrix of 3-vectors in xyz
% and returns a vector of theta values and phi values.
%
% INPUT
%   xyz     3 x n matrix of xyz points
%
% OUTPUT
%   th      n x 1 vector of polar angles in radians
%   ph      n x 1 vector of azimuthal angles in radians
%   rho     n x 1 vector of radial values
%

% ensure that xyz is 3 x n
[n,m] = size(xyz); if n~=3, xyz = xyz'; end

[azi,ele,rho] = cart2sph(xyz(1,:), xyz(2,:), xyz(3,:));

% ensure that th and ph are column vectors
th = pi/2 - ele(:);
ph = azi(:);
