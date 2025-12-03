# =============================================================================
# SCSES HPC Dockerfile
# Purpose: HPC cluster computing, Singularity-compatible, no RStudio
# Base: rocker/r-ver:4.4 (R only, no RStudio Server)
#
# IMPORTANT: This Dockerfile must be built on a native x86_64 Linux machine!
#            Building on Mac ARM with QEMU emulation will fail at MCR install.
#
# Build command (on x86_64 Linux):
#   docker build -f SCSES_hpc.dockerfile -t scses:hpc .
#
# Convert to Singularity:
#   singularity build scses_hpc.sif docker-daemon://scses:hpc
#
# =============================================================================

FROM rocker/r-ver:4.4

LABEL maintainer="SCSES Team"
LABEL description="SCSES HPC environment for single-cell splicing analysis"
LABEL singularity.compatible="true"

# Use bash for all RUN commands
SHELL ["/bin/bash", "-c"]

# =============================================================================
# System dependencies
# =============================================================================
RUN apt-get update && \
    apt-get install -y \
        wget \
        curl \
        ca-certificates \
        aptitude \
        python3-pip \
        openjdk-8-jdk \
        zlib1g-dev \
        libhdf5-dev \
        libtirpc-dev \
        libbz2-dev \
        liblzma-dev \
        libncurses5-dev \
        libncursesw5-dev \
        libgsl-dev \
        cmake \
        libboost-iostreams-dev \
        bedtools \
        libglpk40 \
        libglpk-dev \
        unzip \
        git \
        build-essential && \
    # Create symlink for libboost compatibility
    ln -sf /lib/x86_64-linux-gnu/libboost_iostreams.so.1.83.0 \
           /lib/x86_64-linux-gnu/libboost_iostreams.so.1.71.0 2>/dev/null || true && \
    # Python symlink
    ln -sf /usr/bin/python3 /usr/bin/python && \
    # Create software directory with proper permissions
    mkdir -p /software && \
    chmod 755 /software && \
    # Clean apt cache
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# =============================================================================
# Install Miniconda
# =============================================================================
RUN cd /software && \
    wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh && \
    bash miniconda.sh -b -u -p /software/miniconda3 && \
    rm miniconda.sh && \
    /software/miniconda3/bin/conda init bash && \
    chmod -R 755 /software/miniconda3

ENV PATH="/software/miniconda3/bin:${PATH}"

# =============================================================================
# Install htslib
# =============================================================================
RUN cd /software && \
    wget -q https://github.com/samtools/htslib/releases/download/1.21/htslib-1.21.tar.bz2 && \
    tar -xjf htslib-1.21.tar.bz2 && \
    cd htslib-1.21 && \
    ./configure --prefix=/software/htslib && \
    make -j$(nproc) && \
    make install && \
    cd /software && \
    rm -rf htslib-1.21.tar.bz2 htslib-1.21 && \
    chmod -R 755 /software/htslib

# =============================================================================
# Install featureCounts (subread)
# =============================================================================
RUN cd /software && \
    wget -q https://sourceforge.net/projects/subread/files/subread-2.0.6/subread-2.0.6-source.tar.gz && \
    tar -xzf subread-2.0.6-source.tar.gz && \
    cd subread-2.0.6-source/src && \
    make -f Makefile.Linux -j$(nproc) && \
    cd /software && \
    rm subread-2.0.6-source.tar.gz && \
    chmod -R 755 /software/subread-2.0.6-source

# =============================================================================
# Install samtools
# =============================================================================
RUN cd /software && \
    wget -q https://github.com/samtools/samtools/releases/download/1.21/samtools-1.21.tar.bz2 && \
    tar -xjf samtools-1.21.tar.bz2 && \
    cd samtools-1.21 && \
    ./configure --prefix=/software/samtools && \
    make -j$(nproc) && \
    make install && \
    cd /software && \
    rm -rf samtools-1.21.tar.bz2 samtools-1.21 && \
    chmod -R 755 /software/samtools

# =============================================================================
# Create conda environments
# Note: Must accept ToS for Anaconda channels first
# =============================================================================
RUN conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r && \
    conda update -n base -c defaults conda -y && \
    conda create -n MAJIQ python=3.11 -y && \
    conda create -n SCSES python=3.11 -y && \
    conda clean -afy

# =============================================================================
# Install Python packages in SCSES environment
# =============================================================================
SHELL ["conda", "run", "-n", "SCSES", "/bin/bash", "-c"]
RUN pip install --no-cache-dir \
        pandas \
        numpy \
        scipy \
        scikit-learn \
        cython \
        keras==2.15.0 \
        tensorflow==2.15.0.post1

# =============================================================================
# Install MAJIQ in conda environment
# =============================================================================
SHELL ["conda", "run", "-n", "MAJIQ", "/bin/bash", "-c"]
RUN export HTSLIB_LIBRARY_DIR=/software/htslib/lib && \
    export HTSLIB_INCLUDE_DIR=/software/htslib/include && \
    conda install -c conda-forge gcc=12.1.0 -y && \
    pip install --no-cache-dir git+https://bitbucket.org/biociphers/majiq_academic.git@v2.5.7 && \
    cd /software && \
    wget -q https://majiq.biociphers.org/app_download/majiq_license_academic_official.lic && \
    conda clean -afy

# =============================================================================
# Install STAR
# =============================================================================
SHELL ["/bin/bash", "-c"]
RUN cd /software && \
    wget -q https://github.com/alexdobin/STAR/archive/2.7.11b.tar.gz -O STAR.2.7.11b.tar.gz && \
    tar -xzf STAR.2.7.11b.tar.gz && \
    rm STAR.2.7.11b.tar.gz && \
    chmod -R 755 /software/STAR-2.7.11b

ENV PATH="${PATH}:/software/STAR-2.7.11b/bin/Linux_x86_64_static"

# =============================================================================
# Install rMATS
# =============================================================================
SHELL ["conda", "run", "-n", "SCSES", "/bin/bash", "-c"]
RUN cd /software && \
    wget -q https://github.com/Xinglab/rmats-turbo/releases/download/v4.3.0/rmats_turbo_v4_3_0.tar.gz && \
    tar -xzf rmats_turbo_v4_3_0.tar.gz && \
    cd rmats_turbo_v4_3_0 && \
    bash build_rmats && \
    cd /software && \
    rm rmats_turbo_v4_3_0.tar.gz && \
    chmod -R 755 /software/rmats_turbo_v4_3_0

# =============================================================================
# Install MATLAB Runtime (MCR) R2022b
# NOTE: This step requires native x86_64 - will fail under QEMU emulation!
# =============================================================================
SHELL ["/bin/bash", "-c"]
RUN mkdir -p /MCR && \
    cd /MCR && \
    wget -q https://ssd.mathworks.com/supportfiles/downloads/R2022b/Release/10/deployment_files/installer/complete/glnxa64/MATLAB_Runtime_R2022b_Update_10_glnxa64.zip && \
    unzip -q MATLAB_Runtime_R2022b_Update_10_glnxa64.zip && \
    ./install -destinationFolder /opt/mcr -agreeToLicense yes -mode silent && \
    cd / && \
    rm -rf /MCR && \
    chmod -R 755 /opt/mcr

# =============================================================================
# Install R packages
# =============================================================================
# Step 1: Install base packages and remotes
RUN R -e "install.packages(c('remotes','BiocManager','jsonlite','Matrix','reticulate','irlba','reshape2','R.matlab','hdf5r','R.oo','glmnet','caret','devtools','umap','leiden'), repos='https://cloud.r-project.org', dependencies=TRUE, Ncpus=$(nproc))" && \
    rm -rf /tmp/Rtmp*

# Step 2: Install Bioconductor packages
RUN R -e "BiocManager::install(c('Rsamtools','Rhtslib','S4Vectors','rtracklayer','Biostrings','GenomicRanges','IRanges','rhdf5','BSgenome'), Ncpus=$(nproc), update=FALSE, ask=FALSE)" && \
    rm -rf /tmp/Rtmp*

# Step 3: Install Seurat 4.4.0 (SCSES requires this specific version, NOT 5.x)
RUN R -e "remotes::install_version('Seurat', version='4.4.0', repos='https://cloud.r-project.org', upgrade='never', dependencies=TRUE)" && \
    rm -rf /tmp/Rtmp*

# Step 4: Install SCSES dependencies from GitHub
RUN R -e "\
    remotes::install_github('jonclayden/RNifti', upgrade='never'); \
    remotes::install_github('dipterix/threeBrain', upgrade='never'); \
    remotes::install_github('beauchamplab/raveio', upgrade='never')" && \
    rm -rf /tmp/Rtmp*

# Step 5: Install SCSES
RUN R -e "\
    remotes::install_github('lvxuan12/SCSES', ref='SCSES_docker', dependencies=TRUE, upgrade='never'); \
    if (!require('SCSES', quietly=TRUE)) stop('SCSES installation failed!'); \
    message('SCSES installed successfully!')" && \
    rm -rf /tmp/Rtmp*

# =============================================================================
# Install IRFinder
# =============================================================================
RUN cd /software && \
    wget -q https://github.com/RitchieLabIGH/IRFinder/archive/refs/tags/v2.0.1.tar.gz && \
    tar -xzf v2.0.1.tar.gz && \
    rm v2.0.1.tar.gz && \
    chmod -R 755 /software/IRFinder-2.0.1

# =============================================================================
# Fix libstdc++ compatibility issue
# =============================================================================
SHELL ["conda", "run", "-n", "SCSES", "/bin/bash", "-c"]
RUN if [ -f "${CONDA_PREFIX}/lib/libstdc++.so.6" ]; then \
        mv ${CONDA_PREFIX}/lib/libstdc++.so.6 ${CONDA_PREFIX}/lib/libstdc++.so.6.bak; \
        ln -s /usr/lib/x86_64-linux-gnu/libstdc++.so.6 ${CONDA_PREFIX}/lib/libstdc++.so.6; \
    fi

# =============================================================================
# Set environment variables
# =============================================================================
SHELL ["/bin/bash", "-c"]

ENV JAVA_HOME="/usr/lib/jvm/java-8-openjdk-amd64"
ENV PATH="${PATH}:${JAVA_HOME}/bin:/software/rmats_turbo_v4_3_0:/software/IRFinder-2.0.1/bin:/software/samtools/bin:/software/subread-2.0.6-source/bin:/software/htslib/bin"

# Initialize LD_LIBRARY_PATH with htslib
ENV LD_LIBRARY_PATH="/software/htslib/lib"

# MCR environment variables
ENV MCR_ROOT="/opt/mcr/R2022b"
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${MCR_ROOT}/runtime/glnxa64:${MCR_ROOT}/bin/glnxa64:${MCR_ROOT}/sys/os/glnxa64"

# =============================================================================
# Final permissions and cleanup
# =============================================================================
RUN chmod -R 755 /software && \
    chmod -R 755 /opt/mcr && \
    rm -rf /tmp/* /var/tmp/* ~/.cache

# =============================================================================
# Set working directory and default command
# Singularity-compatible: no ENTRYPOINT, no exposed ports, no daemons
# =============================================================================
WORKDIR /home

# Default to bash shell (Singularity-compatible)
CMD ["bash"]