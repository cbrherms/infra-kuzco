FROM python:3.13-slim-trixie

ARG COMFYUI_REF=v0.40.0
ARG TORCH_VERSION=2.14.1

RUN apt-get update \
    && apt-get install -y --no-install-recommends git libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone https://github.com/comfyanonymous/ComfyUI.git \
    && git -C ComfyUI checkout "${COMFYUI_REF}"

WORKDIR /opt/ComfyUI
# PyPI's Linux torch wheels bundle CUDA 13.0, which needs host driver >= 580
RUN pip install --no-cache-dir "torch==${TORCH_VERSION}" torchvision torchaudio \
    && pip install --no-cache-dir -r requirements.txt

EXPOSE 8188
CMD ["python", "main.py", "--listen", "0.0.0.0", "--port", "8188"]
