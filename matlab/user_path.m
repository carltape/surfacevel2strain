%
% user_path.m
%
% File to set Matlab paths into subdirectories.
%
% Probably it would be cleaner to all user_path.n only ONCE, since this
% will keep adding the same directories into the path each time you run
% surfacevel2strain.m.
%

% this assumes you have a folder called REPOS that contains surfacevel2strain
dir_repos = getenv('REPOS');
bdir = strcat(dir_repos,'/surfacevel2strain/');
bdir_matlab = strcat(bdir,'matlab/');

addpath(strcat(bdir_matlab));
addpath(strcat(bdir_matlab,'util_basic'));
addpath(strcat(bdir_matlab,'util_est'));
addpath(strcat(bdir_matlab,'util_euler'));
