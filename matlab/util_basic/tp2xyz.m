function xyz = tp2xyz(th,ph,rho)
%TP2XYZ convert from theta, phi, rho to (x,y,z)
%
% This function takes the theta and phi of a set of vectors
% on a sphere with radius r and and returns the xyz coordinates
% as a 3 x n matrix.
%
% INPUT
%   th      n x 1 vector of polar angles in radians
%   ph      n x 1 vector of azimuthal angles in radians
%   rho     scalar or n x 1 vector of radial values
%
% OUTPUT
%   xyz     3 x n matrix of xyz points
%

% column vectors
th = th(:);
ph = ph(:);

azi = ph;
ele = pi/2 - th;

if length(rho) == 1
    rho = rho*ones(length(th),1);
    disp('tp2xyz.m: uniform radial value');
end

% azi, ele, r are vectors
[xx,yy,zz] = sph2cart(azi,ele,rho);
xyz = [xx yy zz]';
