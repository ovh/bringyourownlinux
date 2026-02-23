# GitHub Actions Workflows

This directory contains GitHub Actions workflows for building Linux images.

## build-linux-images.yml

This workflow builds images for three different Linux distributions:
- Alpine Linux
- Arch Linux  
- Ubuntu 20.04 with kernel 5.15

### Schedule
- Runs every Monday at 2 AM UTC (weekly)
- Can also be triggered manually via GitHub UI

### What it does
1. Checks out the repository
2. Sets up Packer and QEMU
3. Builds all three Linux images in sequence
4. Uploads the resulting qcow2 images as artifacts

### Artifacts
Each build produces a qcow2 image that is retained for 7 days:
- `alpine-image`
- `archlinux-image` 
- `ubuntu-image`