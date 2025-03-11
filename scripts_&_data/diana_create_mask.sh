#!/bin/bash
module load ants
module load afni
module load fsl/6.0.7.13

#!! Move the subject folder from RABIES output folder 'func_preproc' to the RABIES_preproc folder before you continue with this script. !!


root_dir=/'path/to/homefolder'

#move anat and func scan from RABIES. For func the nifti found in .../bold_datasink/native_bold/... is the func scan registered onto the anatomical scan
cd $root_dir/RABIES_preproc/

cp $root_dir/RABIES_preproc/sub-wave475194_ses-1_run-01_bold.nii/anat_datasink/anat_preproc/_scan_info_subject_idwave475194.session1_split_name_sub-wave475194_ses-1_T2w/sub-wave475194_ses-1_T2w_RAS_inho_cor.nii.gz ./

cp $root_dir/RABIES_preproc/sub-wave475194_ses-1_run-01_bold.nii/bold_datasink/native_bold/_scan_info_subject_idwave475194.session1_split_name_sub-wave475194_ses-1_T2w/_run_1/sub-wave475194_ses-1_run-01_bold_RAS_combined.nii.gz ./

#Further preprocess anatomical scan
DenoiseImage -d 3 -i sub-wave475194_ses-1_T2w_RAS_inho_cor.nii.gz  -o temp_475194.nii.gz

ImageMath 3 anat_475194.nii.gz TruncateImageIntensity temp_475194.nii.gz 0.05 0.999

#preprocess bold scan 
temp_file="475194_bold_temp.nii.gz"

#1) Run 3dWarp to deoblique
3dWarp -deoblique -prefix "$temp_file" sub-wave475194_ses-1_run-01_bold_RAS_combined.nii.gz -overwrite
#2) Run 3dTproject for highpass filter
3dTproject -prefix "$temp_file" -passband 0.01 inf -input "$temp_file" -overwrite

mv "$temp_file" "bold_475194.nii.gz"


#copy files to next slice prep folder
cp anat_475194.nii.gz $root_dir/slice_prep/
cp bold_475194.nii.gz $root_dir/slice_prep/

cd $root_dir/slice_prep/

#cut slice from anat and bold corresponding to DIANA slice (use fsleyes to check)
fslroi anat_475194.nii.gz anat_475194_slice.nii.gz 0 -1 66 1 0 -1
3dresample -orient LPI -prefix anat_475194_slice.nii.gz -input anat_475194_slice.nii.gz -overwrite

fslroi bold_475194.nii.gz bold_475194_slice.nii.gz 0 -1 10 1 0 -1 0 -1

#The BOLD slice is now in RAI orientation. It needs to stay in this orientation for the ANTs registration to succeed!!
#The 2dl-diana scan should be in LPI orientation
3dresample -orient LPI -prefix /bids/2dl/sub-wave475194_ses-1_task-10st50ep_diana.nii.gz  -input /bids/2dl/sub-wave475194_ses-1_task-10st50ep_diana.nii.gz -overwrite

#Get DIANA temporal mean to use for registration
fslmaths /bids/2dl/sub-wave475194_ses-1_task-10st50ep_diana.nii.gz -Tmean diana_tmean.nii.gz

#ANTs call to register anatomical slice to DIANA slice
antsRegistration -d 3 --float 0 -a 0 -v 1 --output anat2diana --interpolation Linear --winsorize-image-intensities [0.005,0.995] --use-histogram-matching 0 --initial-moving-transform [diana_tmean.nii.gz,anat_475194_slice.nii.gz,1] --transform Rigid[0.1] --metric MI[diana_tmean.nii.gz,anat_475194_slice.nii.gz,1,32] --convergence [50,1e-6,10] --shrink-factors 1 --smoothing-sigmas 0vox 


antsApplyTransforms -d 3 -e 4 -i anat_475194_slice.nii.gz -r diana_tmean.nii.gz -t anat2diana0GenericAffine.mat -o anat2dianatest.nii.gz -v 1

cp anat2diana.nii.gz $root_dir/create_mask/

#ANTs call to register bold slice to DIANA slice
antsRegistration -d 3 --float 0 -a 0 -v 1 --output bold2diana --interpolation Linear --winsorize-image-intensities [0.005,0.995] --use-histogram-matching 0 --initial-moving-transform [diana_tmean.nii.gz,bold_475194_slice.nii.gz,1] --transform Rigid[0.1] --metric MI[diana_tmean.nii.gz,bold_475194_slice.nii.gz,1,32] --convergence [50,1e-6,10] --shrink-factors 1 --smoothing-sigmas 0vox 


antsApplyTransforms -d 3 -e 3 -i bold_475194_slice.nii.gz -r diana_tmean.nii.gz -t bold2diana0GenericAffine.mat -o bold2diana.nii.gz -v 1

cp bold2diana.nii.gz $root_dir/create_mask
cp diana_tmean.nii.gz $root_dir/create_mask

cd $root_dir/create_mask

#run glm for bold sequence
fsl_glm -i bold2diana.nii.gz -d $root_dir/bold_glm_design/glm.mat -c $root_dir/bold_glm_design/glm.con -o 475195_glm_output --out_z=475195_z_table --demean 

#open FSLeyes and overlay z-table results with diana temporal mean. Treshold z-table at 2
#draw a ROI mask over the z-table results
#2 control masks were drawn at left and right cortical areas 

#extract timeseries with fslmeants

fslmeants -i $root_dir/bids/2dl/sub-wave475194_ses-1_task-10st50ep_diana.nii.gz -o ts_roi.csv -m diana_mask.nii.gz
fslmeants -i $root_dir/bids/2dl/sub-wave475194_ses-1_task-10st50ep_diana.nii.gz -o ts_control1.csv -m control1_mask.nii.gz
fslmeants -i $root_dir/bids/2dl/sub-wave475194_ses-1_task-10st50ep_diana.nii.gz -o ts_control2.csv -m control2_mask.nii.gz


#average the 2500 times points over 50 cycles to get the averages time series.







