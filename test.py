import openai
import pytesseract
from PIL import Image

openai.api_key = "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"


# Path to your local image
img_path = "screenshot.jpeg"

# Extract text from the local image
img = Image.open(img_path)
extracted_text = pytesseract.image_to_string(img)


print("sini:",extracted_text)

# response = openai.chat.completions.create(
#   model="gpt-4o-mini",
#   messages=[
#     {
#       "role": "user",
#       "content": [
#         {"type": "text", "text": "What’s in this image?"},
#         {
#           "type": "image_url",
#           "image_url": {
#             "url": "image_url",
#             "detail": "high"
#           },
#         },
#       ],
#     }
#   ],
#   max_tokens=300,
# )

# print(response.choices[0].message.content)