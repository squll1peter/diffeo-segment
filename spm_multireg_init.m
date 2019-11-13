function varargout = spm_multireg_init(varargin)
%__________________________________________________________________________
%
% Initialisation functions for spm_multireg.
%
% FORMAT dat = spm_multireg_init('InitDat',F,K,sett)
% FORMAT dat = spm_multireg_init('InitDef',dat,sett)
%
%__________________________________________________________________________
% Copyright (C) 2019 Wellcome Trust Centre for Neuroimaging

if nargin == 0
    help spm_multireg_init
    error('Not enough argument. Type ''help spm_multireg_init'' for help.');
end
id = varargin{1};
varargin = varargin(2:end);
switch id
    case 'InitDat'
        [varargout{1:nargout}] = InitDat(varargin{:});   
    case 'InitDef'
        [varargout{1:nargout}] = InitDef(varargin{:});           
    otherwise
        help spm_multireg_init
        error('Unknown function %s. Type ''help spm_multireg_init'' for help.', id)
end
end
%==========================================================================

%==========================================================================
% InitDat()
function dat = InitDat(F,K,sett)
M0 = eye(4);
for n=1:numel(F)
    
    % Init datn.f
    if iscell(F(n)) && isnumeric(F{n})
        % Input F is numeric -> store as numeric
        
        if sett.gen.run2d            
            % Get 2D slice from 3D data
            dat(n).f = get_slice(F{n},sett.gen.run2d);
        else
            dat(n).f = single(F{n});
        end
    elseif isa(F(n),'nifti') || (iscell(F(n)) && (isa(F{n},'char') || isa(F{n},'nifti')))
        % Input F is nifti (path or object) -> store as nifti
                       
        if isa(F(n),'nifti')
            dat(n).f = F(n);        
        elseif iscell(F(n)) 
            if isa(F{n},'char')
                dat(n).f = nifti(F{n});        
            elseif isa(F{n},'nifti')
                dat(n).f = nifti;
                C        = numel(F{n});
                for c=1:C
                    dat(n).f(c) = F{n}(c);
                end
            end
        end
        
        if sett.gen.run2d
            % Get 2D slice from 3D data
            fn       = spm_multireg_io('GetData',dat(n).f);
            dat(n).f = get_slice(fn,sett.gen.run2d);
        end
    end
                  
    if sett.do.gmm            
        % GMM
        d  = spm_multireg_io('GetDimensions',dat(n).f);
        C  = d(4);
        fn = spm_multireg_io('GetData',dat(n).f);                     
                          
        % Initial means and precisions from image channel max
        mog        = init_gmm(fn,K);        
        dat(n).mog = mog;
    end
    
    % Other parameters
    dat(n).M   = M0;    
    dat(n).q   = zeros(6,1);    
    dat(n).v   = [];    
    dat(n).psi = [];    
    dat(n).E   = [0 0];  
    
    % Orientation matrix (image voxel-to-world)
    dat(n).Mat = eye(4); % Should really do this better           
    if isa(dat(n).f,'nifti') && ~sett.gen.run2d
        dat(n).Mat = dat(n).f(1).mat;        
    end
end
end
%==========================================================================

%==========================================================================
% InitDef()
function dat = InitDef(dat,sett)
v    = zeros([sett.var.d,3],'single');
psi1 = spm_multireg_util('Identity',sett.var.d);
for n=1:numel(dat)
    dat(n).q = zeros(size(sett.registr.B,3),1);
    if isnumeric(dat(n).f)
        dat(n).v   = v;
        dat(n).psi = psi1;
    else
        if isa(dat(n).f,'nifti')
            [~,nam,~] = fileparts(dat(n).f(1).dat.fname);
            vname    = fullfile(sett.write.dir_res,['v_' nam '.nii']);
            pname    = fullfile(sett.write.dir_res,['psi_' nam '.nii']);
            fa       = file_array(vname,[sett.var.d(1:3) 1 3],'float32',0);
            nii      = nifti;
            nii.dat  = fa;
            nii.mat  = sett.var.Mmu;
            nii.mat0 = sett.var.Mmu;
            nii.descrip = 'Velocity';
            create(nii);
            nii.dat(:,:,:,:) = v;
            dat(n).v    = nii;

            nii.dat.fname = pname;
            nii.descrip = 'Deformation (WIP)';
            create(nii);
            nii.dat(:,:,:,:) = psi1;
            dat(n).psi  = nii;
        end
    end
end
end
%==========================================================================

%==========================================================================
%
% Utility functions
%
%==========================================================================

%==========================================================================
% get_slice()
function fn = get_slice(fn,direction)
d  = size(fn);
d  = [d 1];
ix = round(d(1:3)*0.5);

if d(3) == 1, return; end

if direction == 1
    fn = single(fn(ix(1),:,:,:));
elseif direction == 2
    fn = single(fn(:,ix(2),:,:));
elseif direction == 3
    fn = single(fn(:,:,ix(3),:));
end

% Reshape
C  = d(4);
ix = 1:3;
d  = d(1:3);
fn = reshape(fn, [d(ix ~= direction) 1 C]);
end
%==========================================================================    

%==========================================================================    
% init_gmm()
function mog = init_gmm(fn,K)
K  = K + 1;
d  = size(fn);
d  = [d 1];
C  = size(fn,4);
fn = reshape(fn,[prod(d(1:3)) C]);

% Posterior
mu = zeros(C,K);
A  = zeros(C,C,K);        
for c=1:C
    mx       = nanmax(fn(:,c));                            
    mu(c,:)  = (0:(K - 1))'*mx/(2*K);
    A(c,c,:) = mx/K;        
    A(c,c,:) = 1/A(c,c,:);
end   

mog.po.m = mu;
mog.po.b = ones(1,K);
mog.po.n = C*ones(1,K);
mog.po.V = bsxfun(@times, A, reshape(mog.po.n, [1 1 K])); % Expected precision

% Prior (uninformative)
mog.pr.m = zeros(C,K);
mog.pr.b = ones(1,K);
mog.pr.n = C*ones(1,K);
mog.pr.V = bsxfun(@times, repmat(eye(C),[1 1 K]), reshape(mog.pr.n, [1 1 K]));
end
%==========================================================================            