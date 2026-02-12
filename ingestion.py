import os
from dotenv import load_dotenv
from pinecone import Pinecone, ServerlessSpec
from langchain.document_loaders import PyPDFLoader
from langchain.text_splitter import CharacterTextSplitter
from langchain.embeddings.openai import OpenAIEmbeddings
 
# Load environment variables from .env
load_dotenv()
 
# Create Pinecone client instance
pc = Pinecone(
    api_key="pcsk_2i2xPK_KYiGVNEnXufSkySKgrNh6fY9wGT7TrgKe58cRrXUWXioy1REWgPFXKu4TkFJvG7"  # Get API key from environment
)
 
# Check and create Pinecone index if necessary
index_name = "payhack"
if index_name not in pc.list_indexes().names():
    pc.create_index(
        name="payhack",
        dimension=1536,  # Dimension should match OpenAI embeddings
        metric="cosine",  # Metric can be 'cosine', 'euclidean', or 'dotproduct'
        spec=ServerlessSpec(
            cloud="aws",  # Specify the cloud provider
            region="us-east-1"  # Specify the region (use your Pinecone environment)
        )
    )
    print(f"Index '{index_name}' created successfully.")
else:
    print(f"Index '{index_name}' already exists.")
 
# Load the PDF document
loader = PyPDFLoader("FraudDocument1.pdf")
documents = loader.load()
 
# Split the text into smaller chunks
text_splitter = CharacterTextSplitter(chunk_size=1000, chunk_overlap=100)
texts = text_splitter.split_documents(documents)
print(f"Created {len(texts)} text chunks.")
 
# Generate embeddings for the text chunks using OpenAI
embeddings = OpenAIEmbeddings(openai_api_key="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")
 
# Connect to the Pinecone index
index = pc.get_index(index_name)
 
# Prepare data for upsertion
vectors = [
    {"id": str(i), "values": embeddings.embed_text(text.page_content)}
    for i, text in enumerate(texts)
]
 
# Insert vectors into the Pinecone index
index.upsert(vectors=vectors)
print(f"Upserted {len(vectors)} vectors into Pinecone index '{index_name}'.")
 