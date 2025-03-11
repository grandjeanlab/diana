Welcome to our DIANA repo.
In this readme file we'll explain exactly how to re-create our DIANA-signal, as first introduced by Toi et al. (2022) (DOI: 10.1126/science.abh4340) using optogenetic stimulation of the mouse infralimbic cortex.

All data analysis performed on Linux Version: CentOS Linux 7 (Core)

Data visualization performed on Python V3.12.0


HARDWARE:

MRI scanner: Bruker BioSpec 117/16

LED source: Prizmatix Optogenetics-LED-Blue (power 100%)

Fiber: Prizmatix Optogenetics fiber NA=0.63

Pulser: Prizmatix Optogenetics Pulser/ PulserPlus (software: Prizmatix Pulser / PulserPlus App for Mac and Windows web application)

	BOLD pulse sequence lay out
		pre-stimulus period:	0 timepoints
		Stimulus period:	5 timepoints
		Post-stimulus period:	55timepoints
		Total timepoints: 	610 (11 cycles, last cycle cut short 40 timepoints)	
		
	DIANA pulse sequence lay out 
		pre-stimulus period:	10 timepoints
		Stimulus period:	10 timepoints
		post-stimulus period:	30 timepoints
		Total timepoints:	2500 (50 cycles)

Example Pulser Settings BOLD:

![Group settings](/fig/BOLD_pulser1.png) ![Laser Settings](/fig/BOLD_pulser2.png)

Example Pulser Settings DIANA:

![Group settings](/fig/DIANA_pulser1.png) ![Laser Settings](/fig/DIANA_pulser2.png)

ANIMAL:

Animal: C57BL/6J // Charles River // Ger

Age at scan: 11 weeks

Virus & titer: AAV5-hSyn-hChR2(H134R)-EYFP (addgene.org #26973-AAV5), 4.0*10^9 vg

injection location: AP: +2.0 , ML: +0.2, DV: -2.7

Implant: Doric Lenses, borosilicate, 200 um - NA=0.66, receptacle diameter 1.25 mm

Implant location: AP: +2.0, ML: +0.2, DV: -2.5


SOFTWARE:

Linux

	Brkraw:	V0.3.11
	ANTs:	V2.5.3-g98bf76d
	afni:	V22.1.09 
	FSL:	V6.0.7.13
	RABIES:	V0.4.8 *Note: Our script uses RABIES as apptainer install

Python packages:

		matplotlib	3.9.0
		pandas		2.2.2
		numpy 		1.26.4
		seaborn		0.13.2


How to start:

This methods requires three scans: 
1) anatomical (FLASH)
2) functional (EPI) combined with optogenetic stimulation
3) 2D-line scan (slice at implant location) combined with optogenetic stimulation

The goal is to create a ROI-mask in the 2D-line scan, based on voxels that appear activated in the functional scan in the same slice. After that a timeseries can be extracted from the voxels within this ROI-mask. This timeseries (consisting of 50 cycles) will be average to receive an averaged cycle (DIANA_signal.png).
To do this we will first extract the slice from the functional scan corresponding with the 2D-line scan slice. This slice wil be registered onto the 2D-line scan after which we run a GLM and extract z-table results using FSL. Using the z-table results a ROI-mask can be drawn onto the 2D-line scan. 

STEP-BY-STEP:

1. Start with converting raw scanner data to BIDS format using Brkraw
```bash
root_dir='path/to/homefolder'
cd $root_dir/raw_data/
brkraw bids_helper raw conv.csv -j
#only keep scan 6(anat), 11(bold) & 14(diana) in .csv
brkraw bids_convert raw conv.csv -j conv.json -o converted

#move bids to bids folder
mkdir $root_dir/bids
find "$root_dir/raw_data/converted/sub-wave475194/" -type d -name "anat" -exec rsync -av {} "$root_dir/bids/" \;
find "$root_dir/raw_data/converted/sub-wave475194/" -type d -name "func" -exec rsync -av {} "$root_dir/bids/" \;
find "$root_dir/raw_data/converted/sub-wave475194/" -type d -name "2dl" -exec rsync -av {} "$root_dir/bids/" \;
```

2. Next run the preprocessing step from RABIES onto the functional & anatomical scan. In this step the func scan will be registered onto the anatomical scan and first preprocessing on anatomical scan will be performed (inhomogeneity correction). Also orientation will be changed from LSP --> LPI
The RABIES call used for our data can be found in 'rabies_call.sh'. 

```bash
root_dir="/path/to/homefolder/RABIES_preproc/"
og_bids="path/to/homefolder/bids"
RABIES="/path/to/apptainer/rabies.sif"

#arguments for RABIES preprocessing
prep_arg='--TR 1 --commonspace_reg masking=false,brain_extraction=false,template_registration=SyN,fast_commonspace=true --commonspace_resampling 0.3x0.3x0.3' 

mkdir -p $root_dir/tmp_script
mkdir -p $root_dir/tmp_bids
mkdir -p $root_dir/func_preprocess
mkdir -p $root_dir/func_confound
mkdir -p $root_dir/func_analysis

ls -d $root_dir/$og_bids/sub*/ | while read scan
do

  func_scans=()

  functional=$(find $scan -name *_bold.nii.gz) 
  anat=$(find $scan -name *_T2w.nii.gz)  
  func_scans+=($functional)
  echo $func_scans

  for func in ${func_scans[*]}
  do

    func_basename=$(basename -- "$func") 
    func_noext="${func_basename%.*}"

    #check that all the files are where they should be 
    if [ -z "$func" ]; then
    echo "func missing in "$scan
    continue
    fi

    if [ -z "$anat" ]; then
    echo "anat missing in "$scan
    continue
    fi


    #get subject and session name from directory name 
    sub=$func_noext
    bids=${root_dir}/tmp_bids/${sub}

    #RABIES directories.
    preprocess=$root_dir/func_preprocess/${sub}
    confound=$root_dir/func_confound/${sub}
    analysis=$root_dir/func_analysis/${sub}
    
    mkdir -p $preprocess


    #####write to tmp scripts#####
    #env variables and modules
    echo "module load apptainer"  > ${root_dir}/tmp_script/scrip_${sub}.sh
    echo "module load ANTs"  >> ${root_dir}/tmp_script/scrip_${sub}.sh
    echo "module unload ANTs"  >> ${root_dir}/tmp_script/scrip_${sub}.sh
    echo "module unload freesurfer"  >> ${root_dir}/tmp_script/scrip_${sub}.sh
    echo "module unload fsl"  >> ${root_dir}/tmp_script/scrip_${sub}.sh

    #make dir and cp anat and func folders
    echo "mkdir -p "${bids}  >> ${root_dir}/tmp_script/scrip_${sub}.sh
    echo "mkdir -p "${bids}"/func"  >> ${root_dir}/tmp_script/scrip_${sub}.sh
    echo "mkdir -p "${bids}"/anat"  >> ${root_dir}/tmp_script/scrip_${sub}.sh
    echo "cp -r "${func}" "${root_dir}"/tmp_bids/"${sub}"/func"   >> ${root_dir}/tmp_script/scrip_${sub}.sh
    echo "cp -r "${anat}" "${root_dir}"/tmp_bids/"${sub}"/anat"   >> ${root_dir}/tmp_script/scrip_${sub}.sh

    #preprocess
    echo "apptainer run -B "${bids}":/input_bids:ro -B "${preprocess}":/preprocess_outputs/ "${RABIES}" -p MultiProc preprocess /input_bids/ /preprocess_outputs/ "${prep_arg} >> ${root_dir}/tmp_script/scrip_${sub}.sh

    done
  
  done

for file in ${root_dir}/tmp_script/*
do
  qsub -l 'walltime=48:00:00,mem=32gb,procs=2' $file
done

#remove tmp folders and move subject folder from func_preprocc into RABIES_preprocc folder for further processing
rmdir $root_dir/tmp_script
rmdir $root_dir/tmp_bids
rmdir $root_dir/func_confound
rmdir $root_dir/func_analysis

mv $root_dir/func_preprocess/sub-wave475194_ses-1_run-01_bold.nii $root_dir
```

3. Now, we will process the anatomical and functional scan to to create a ROI mask for the 2D-line scan. The anatomical scan main use is to double check for implant location and orientation of 2D-line scan and functional scan slices
```bash
module load ants/2.5.3
module load afni/2022
module load fsl/6.0.7.13

root_dir=/'path/to/homefolder'
cd $root_dir/RABIES_preproc

#move anat and func scan from RABIES. For func the nifti found in .../bold_datasink/native_bold/... is the func scan registered onto the anatomical scan

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
#The 2Dl-diana scan should be in LPI orientation (these orientations are important otherwise the ANTs registration calls below
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
```
![BOLD signal in 2D-line slice](/fig/z_table_results.png)

```bash
#open FSLeyes and overlay z-table results with diana temporal mean. Treshold z-table at 2
#draw a ROI mask over the z-table results
#For control we drew 2 masks bilaterally in the the cortical regions of the 2D-line scan
``` 
![](/fig/ROI_masks.png)

```bash
#extract timeseries with fslmeants
fslmeants -i $root_dir/bids/2dl/sub-wave475194_ses-1_task-10st50ep_diana.nii.gz -o $root_dir/scripts_&_data/ts_roi.csv -m diana_mask.nii.gz
fslmeants -i $root_dir/bids/2dl/sub-wave475194_ses-1_task-10st50ep_diana.nii.gz -o $root_dir/scripts_&_data/ts_control1.csv -m control1_mask.nii.gz
fslmeants -i $root_dir/bids/2dl/sub-wave475194_ses-1_task-10st50ep_diana.nii.gz -o $root_dir/scripts_&_data/ts_control2.csv -m control2_mask.nii.gz
```

4. After this the timeseries can be extracted and plotted. This is done in python.
```python
import os
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt
import matplotlib.patches as patches
import numpy as np

os.chdir(r'path/to/homefolder/scripts_&_data')

ts_roi=pd.read_csv('ts_roi.csv', header=None) 
ts_con1=pd.read_csv('ts_control1.csv', header=None)
ts_con2=pd.read_csv('ts_control2.csv', header=None)

# Group elements into chunks of 50 as cycle length is 50
groups_roi = [ts_roi[i:i+50] for i in range(0, len(ts_roi), 50)]
groups_roi = [df.reset_index(drop=True) for df in groups_roi] 
ts_roi_big = pd.concat(groups_roi, axis=1)
ts_roi_big.iloc[0,0] = np.average(ts_roi_big.iloc[1:,0])       #1st time point of 1st cycle is relabled by average of 1st time point of all other cycles
ts_roi_big['average'] = ts_roi_big.mean(axis=1)
average_ts_roi=ts_roi_big['average']

groups_con1 = [ts_con1[i:i+50] for i in range(0, len(ts_con1), 50)]
groups_con1 = [df.reset_index(drop=True) for df in groups_con1] 
ts_con1_big = pd.concat(groups_con1, axis=1)
ts_con1_big.iloc[0,0] = np.average(ts_con1_big.iloc[1:,0])       #1st time point of 1st cycle is relabled by average of 1st time point of all other cycles
ts_con1_big['average'] = ts_con1_big.mean(axis=1)
average_ts_con1=ts_con1_big['average']

groups_con2 = [ts_con2[i:i+50] for i in range(0, len(ts_con2), 50)]
groups_con2 = [df.reset_index(drop=True) for df in groups_con2] 
ts_con2_big = pd.concat(groups_con2, axis=1)
ts_con2_big.iloc[0,0] = np.average(ts_con2_big.iloc[1:,0])       #1st time point of 1st cycle is relabled by average of 1st time point of all other cycles
ts_con2_big['average'] = ts_con2_big.mean(axis=1)
average_ts_con2=ts_con2_big['average']



#normalize values according to average value in pre-stim period.
prestim_av_roi = np.average(average_ts_roi[0:9])
ts_percent_roi = average_ts_roi.div(prestim_av_roi)
ts_percent_roi = ts_percent_roi.sub(1)
ts_percent_roi = ts_percent_roi.mul(100)

prestim_av_con1 = np.average(average_ts_con1[0:9])
ts_percent_con1 = average_ts_con1.div(prestim_av_con1)
ts_percent_con1 = ts_percent_con1.sub(1)
ts_percent_con1 = ts_percent_con1.mul(100)

prestim_av_con2 = np.average(average_ts_con2[0:9])
ts_percent_con2 = average_ts_con2.div(prestim_av_con2)
ts_percent_con2 = ts_percent_con2.sub(1)
ts_percent_con2 = ts_percent_con2.mul(100)


#make figure
sns.set_style("whitegrid")  # Clean background
fig, ax = plt.subplots(figsize=(8, 5), dpi=300)
ax.set_xlim(-10, 40)
ax.axhline(0, color="black", linewidth=1.5, linestyle=":")  
ax.axvline(0, color="black", linewidth=1.5, linestyle=":")
for spine in ['left', 'bottom']:
    ax.spines[spine].set_linewidth(1)  # Adjust thickness
    ax.spines[spine].set_color('black')  # Set color to black
ax.grid(False)

ax.tick_params(axis='x', which='both', direction='out', bottom=True, top=False)
ax.xaxis.set_major_locator(plt.MultipleLocator(10)) 
ax.xaxis.set_minor_locator(plt.MultipleLocator(1))
ax.tick_params(axis='x', which='major', length=10, width=1, direction= 'in')  
ax.tick_params(axis='x', which='minor', length=5, width=1, direction= 'in')   


# Plot signals & stim period
shifted_timepoints = np.arange(-10, 40)
ax.plot(shifted_timepoints,ts_percent_roi, label="ROI Signal", color="crimson", linewidth=1.25)
ax.plot(shifted_timepoints,ts_percent_con1, label="Control 1", color="dimgrey", linewidth=1.25)
ax.plot(shifted_timepoints,ts_percent_con2, label="Control 2", color="darkgray", linewidth=1.25)
ax.axvspan(0, 10, color="deepskyblue", alpha=0.25, label="Stimulation Period")


# Labels, title, legend
ax.set_xlabel("Time from onset stimulus",  fontsize=14)
ax.set_ylabel("Difference signal intensity (%)",  fontsize=14)
ax.set_title("Extracted Time Series from 475194", fontsize=16, weight="bold")
ax.legend(fontsize=11, frameon=False)
sns.despine(ax=ax, top=True, right=True, left=False, bottom=False)


# Show plot
plt.savefig("averaged_ts.png", dpi=300, bbox_inches="tight")
plt.show()
```

5. The resulting averaged signal

![](/fig/averaged_ts.png)








