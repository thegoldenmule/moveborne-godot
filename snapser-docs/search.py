'''
  Script to test the search functionality

  @Author: Ajinkya Apte
  @Company: Snapser Inc.

'''
import os
import json
# import shutil
# from pathlib import Path
from openai import OpenAI
from openai.types import CreateEmbeddingResponse
from annoy import AnnoyIndex

# TODO: See if we can use BERT embeddings instead of OpenAI's text-embedding-ada-002
#   My testing told me that BERT embeddings are not as good as OpenAI's text-embedding-ada-002
# tokenizer = BertTokenizer.from_pretrained('bert-base-uncased')
# model = BertModel.from_pretrained('bert-base-uncased')
# def text_to_embedding(text):
#     '''
#     Convert text to an embedding using BERT
#     '''
#     # Tokenize the input text and convert to tensor
#     inputs = tokenizer(text, return_tensors="pt",
#                        padding=True, truncation=True)

#     # Forward pass, get hidden states
#     with torch.no_grad():
#         outputs = model(**inputs)

#     # Use the mean of the last hidden state as the sentence embedding
#     embeddings = outputs.last_hidden_state.mean(dim=1).squeeze().numpy()
#     return embeddings


def text_to_embedding_oai(text):
    '''
    Convert text to an embedding using OpenAI's text-embedding-ada-002 model
    '''
    client = OpenAI(api_key=os.getenv('OPENAI_API_KEY'))
    response: CreateEmbeddingResponse = client.embeddings.create(
        input=text,
        # model="text-embedding-ada-002"
        model="text-embedding-3-small"

    )
    return response.data[0].embedding


def search(query, index_path='snapser-search.ann', num_results=10):
    '''
    Search for similar content in the index using the query
    '''
    query_embedding = text_to_embedding_oai(query)
    u = AnnoyIndex(len(query_embedding), 'angular')
    u.load(index_path)  # mmap the file

    # Find the nearest neighbors
    indices = u.get_nns_by_vector(query_embedding, num_results)
    return indices


if __name__ == '__main__':
    # Example search
    SNAPSER_INDEX_FILENAME = 'snapser-search.ann'
    QUERY = "Server time"
    print('Query: ', QUERY)
    result_indices = search(QUERY, SNAPSER_INDEX_FILENAME)
    print('Results: ', result_indices)
    # Open the snapser-search.json file to get the data
    with open('snapser-search.json') as f:
        data = json.load(f)
        OPTION = 1
        dedup = {}
        for index in result_indices:
            file_key = data['chunks'][index]
            if file_key in dedup:
                continue
            dedup[file_key] = True
            print(f'==== Option {OPTION}====')
            print('Title: ', data['lookup'][file_key]['title'])
            print('Description: ', data['lookup'][file_key]['description'])
            print('Path: ', file_key)
            print('========')
            OPTION += 1
