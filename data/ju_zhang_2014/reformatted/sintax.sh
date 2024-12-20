#!/usr/bin/bash -l
#SBATCH --job-name=mc-prediction
#SBATCH --output=job_%j_%x.out
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --ntasks-per-node=1
#SBATCH --partition=general
#SBATCH --cpus-per-task=32
#SBATCH --mem=3G
#SBATCH --time=0-1:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=ksa@bio.aau.dk

set -euo pipefail

# remove everything after first space, keep only denovoXXXX
awk '/^>/ {sub(/ .*/, "");} {print}' ../original/58-ST-AS-R10000_rep_set.fasta > OTUs.fa

usearch11 -sintax "OTUs.fa" -db "/databases/midas/MiDAS5.3_20240320/FLASVs_w_sintax.fa" -tabbedout "midas53.sintax" -strand both -sintax_cutoff 0.8 -threads "$(nproc)"