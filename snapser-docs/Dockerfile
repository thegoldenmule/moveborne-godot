# Use an official Python runtime as a parent image
FROM 131164543756.dkr.ecr.us-west-2.amazonaws.com/sandbox-multi-portal:docs-search-base-python.3.8-slim

# Copy the current directory contents into the container at /app
COPY . /app

WORKDIR /app

# Install CPU-only PyTorch first (skips ~400MB of CUDA libraries)
RUN pip install torch --no-cache-dir --index-url https://download.pytorch.org/whl/cpu

# Install any needed packages specified in requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Pre-download the local embedding model so it's baked into the image
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"

# # Install TextBlob and download necessary NLTK corpora
# RUN pip install textblob
# RUN python -m textblob.download_corpora
# # Download necessary NLTK corpora used by TextBlob
# RUN python -m nltk.downloader punkt
# RUN python -m nltk.downloader punkt_tab
# RUN python -m nltk.downloader averaged_perceptron_tagger
# RUN python -m nltk.downloader brown

# Make port 5003 available to the world outside this container
EXPOSE 5003

# Run Gunicorn to serve the app
CMD ["gunicorn", "-w", "1", "-t", "600", "-b", "0.0.0.0:5003", "app:app"]
