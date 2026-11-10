#!/bin/bash
# Phone: build mnn_nlu_worker against the local MNN 3.6.2 build (libMNN.so contains the LLM engine).
set -e
M=$HOME/voice/mnn/MNN-3.6.2
cd "$(dirname "$0")"
RJ=$(dirname "$(find "$M/3rd_party" -path "*rapidjson/document.h" | head -1)")/..
g++ -O2 -std=c++17 -o mnn_nlu_worker mnn_nlu_worker.cpp \
  -I"$M/include" -I"$M/transformers/llm/engine/include" -I"$RJ" \
  -L"$M/build" -lMNN -Wl,-rpath,"$M/build" -lpthread
ls -la mnn_nlu_worker
