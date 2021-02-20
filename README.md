surfacevel2strain ("surface velocity to strain"). 
contact: Carl Tape, University of Alaska Fairbanks, ctape@alaska.edu

download the zipped file or use this command:  
git clone --depth=1 https://github.com/carltape/surfacevel2strain

Carl Tape, Pablo Muse, Mark Simons

A Matlab code for a a spherical-wavelet-based estimation of velocity fields on the sphere from discrete 3-component (or 2-component) GPS observations.

Reference:  
Tape, C., P. Muse, M. Simons, D. Dong, and F. Webb, 2009,
Multiscale estimation of GPS velocity fields, Geophysical Journal International, v. 179, p. 945-971.

Step 0: note the directories in surfacevel2strain:  
  gmt           -- Perl scripts for plotting in GMT 
  data          -- input data files 
  matlab        -- matlab codes (surfacevel2strain.m) 
  matlab_output -- output files from matlab 
  USER_INFO     -- PDF notes and documentation 

Step 1: read the documentation in USER_INFO/:  
  surfacevel2strain_manual.pdf 
  Tape2009gps.pdf 
  Tape2009gps_supplement.pdf 

Step 2:  
  cd matlab 
  Start with sphereinterp.m, the 1D example shown in surfacevel2strain_manual.pdf 

Matlab toolboxes required:  
  mapping       -- areaquad.m, distance.m, etc 
(In the future it would be nice to eliminate dependencies on other toolboxes.)

https://sites.google.com/alaska.edu/carltape/home/research/strain