from flask import Flask, request, jsonify, Response
import openai
import pytesseract
import os
from PIL import Image

 
app = Flask(__name__)
# client = openai()
 
# Set your OpenAI API key
openai.api_key = "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"
 
# Example data
users = [
    {"id": 1, "name": "John Doe", "email": "john@example.com"},
    {"id": 2, "name": "Jane Smith", "email": "jane@example.com"}
]
 
# Home Route
@app.route("/")
def home():
    return "Welcome to the Python Flask Backend!"
 
# Endpoint: Get all users
@app.route("/users", methods=["GET"])
def get_users():
    return jsonify(users)
 
# Endpoint: Get a specific user by ID
@app.route("/users/<int:user_id>", methods=["GET"])
def get_user(user_id):
    user = next((u for u in users if u["id"] == user_id), None)
    if user:
        return jsonify(user)
    else:
        return jsonify({"error": "User not found"}), 404
 
# Endpoint: Add a new user
@app.route("/users", methods=["POST"])
def add_user():
    new_user = request.json
    new_user["id"] = len(users) + 1  # Auto-increment ID
    users.append(new_user)
    return jsonify(new_user), 201
 
# Endpoint: Update a user by ID
@app.route("/users/<int:user_id>", methods=["PUT"])
def update_user(user_id):
    user = next((u for u in users if u["id"] == user_id), None)
    if user:
        data = request.json
        user.update(data)
        return jsonify(user)
    else:
        return jsonify({"error": "User not found"}), 404
 
# Endpoint: Delete a user by ID
@app.route("/users/<int:user_id>", methods=["DELETE"])
def delete_user(user_id):
    global users
    users = [u for u in users if u["id"] != user_id]
    return jsonify({"message": "User deleted"}), 200
 
# Endpoint: Ask ChatGPT
@app.route("/chatgpt", methods=["POST"])
def chatgpt():
    print("request", request)
    user_input = request.json.get("input")  # Get the input from the request JSON
    if not user_input:
        return jsonify({"error": "Input is required"}), 400
   
    try:
        completion = openai.chat.completions.create(
            model="gpt-4",
            messages=[
                {"role": "system",
                "content": [
                    {
                        "type": "text",
                        "text": 
                        "Help Malaysians understand and identify fraud-related issues by providing clear insights and practical advice on how to recognize, report, and prevent fraud in everyday situations, especially related to banking and online scams. Make it less than 20 words"
                    }
                ]},
                {
                    "role": "user",
                    "content": [{
                        "type": "text",
                        "text": user_input
                    }]
                }
            ]
        )
        response_text = completion.choices[0].message.content
        return jsonify({"response": response_text}), 200

        
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# @app.route("/image", methods=["POST"])
# def image():
#     user_input = request.json.get("input")  # Get the input from the request JSON
#     if not user_input:
#         return jsonify({"error": "Input is required"}), 400
   
#     # Check if 'image' is present in the request
#     # if 'image' not in request.files:
#     #     print("Ok")
#     #     return jsonify({"error": "No image part"}), 400
    
#     # # image = request.files['image']
#     # if image.filename == '':
#     #     print("Okok")
#     #     return jsonify({"error": "No selected image"}), 400

#     try:
#         # Save the uploaded image
#         image_path = os.path.join(app.config['UPLOAD_FOLDER'], image.filename)
        
#         image.save(image_path)

#         # Use pytesseract to extract text from the image
#         img = Image.open(image_path)
#         extracted_text = pytesseract.image_to_string(img)

#         # Check if text was extracted
#         if not extracted_text.strip():
#             return jsonify({"error": "No text found in the image"}), 400

#         # Send the extracted text to ChatGPT
#         completion = openai.chat.completions.create(
#             model="gpt-4",
#             messages=[
#                 {"role": "system", "content": "Help Malaysians understand and identify fraud-related issues by providing clear insights and practical advice on how to recognize, report, and prevent fraud in everyday situations, especially related to banking and online scams. Make it less than 20 words."},
#                 {"role": "user", "content": extracted_text}
#             ]
#         )

#         # Get the response from ChatGPT
#         response_text = completion.choices[0].message['content']
#         return jsonify({"response"}), 200

#     except Exception as e:
#         return jsonify({"error": str(e)}), 500


@app.route("/account", methods=["POST"])
def account():
    account_number = request.json.get("input")  # Get the input from the request JSON
    if not account_number:
        return jsonify({"error": "Input is required"}), 400

    try:
        last_digit = int(account_number[-1])  # Extract the last digit
        
        # HTML for even and odd cases
        even_html = """
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Fraudulent Account Warning</title>
            <style>
                body { font-family: Arial, sans-serif; background-color: #f5f5f5; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
                .container { background-color: #ffdd44; border-radius: 10px; width: 350px; padding: 20px; box-shadow: 0 4px 8px rgba(0, 0, 0, 0.2); }
                .header { font-size: 14px; text-align: left; }
                .header p { margin: 5px; font-size: 14px; }
                .content { margin-top: 20px; padding: 15px; background-color: #fff2b3; border-radius: 10px; text-align: left; }
                .content p { margin: 10px 0; font-size: 14px; }
                .robot { display: block; padding-top: 10px; padding-bottom: 10px; width: 200px; height: auto; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <p><strong>Owner:</strong> Ahmad Bin Ali</p>
                    <p><strong>Banking Institute:</strong> April Bank</p>
                    <p><strong>Flagged by Bank Negara:</strong> Yes</p>
                    <p><strong>Police Report:</strong> 3 Times</p>
                </div>
                <div class="content">
                    <p>Based on initial checking, this bank account may have been involved in fraudulent activities.</p>
                    <p><strong>Recommended:</strong> Be caution when dealing with this account.</p>
                    <img src="robot.png" alt="Robot" class="robot">
                </div>
            </div>
        </body>
        </html>
        """
        
        odd_html = """
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Fraudulent Account Warning</title>
            <style>
                body { font-family: Arial, sans-serif; background-color: #f5f5f5; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
                .container { background-color: #ffdd44; border-radius: 10px; width: 350px; padding: 20px; box-shadow: 0 4px 8px rgba(0, 0, 0, 0.2); }
                .header { font-size: 14px; text-align: left; }
                .header p { margin: 5px; font-size: 14px; }
                .content { margin-top: 20px; padding: 15px; background-color: #fff2b3; border-radius: 10px; text-align: left; }
                .content p { margin: 10px 0; font-size: 14px; }
                .robot { display: block; padding-top: 10px; padding-bottom: 10px; width: 200px; height: auto; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <p><strong>Owner:</strong> Afiq Bin Safwan</p>
                    <p><strong>Banking Institute:</strong> CIMB</p>
                    <p><strong>Flagged by Bank Negara:</strong> No</p>
                    <p><strong>Police Report:</strong> 0 Times</p>
                </div>
                <div class="content">
                    <p>The account number has been verified and shows no fraudulent activity based on checks with Bank Negara and PDRM..</p>
                    <img src="robot.png" alt="Robot" class="robot">
                </div>
            </div>
        </body>
        </html>
        """
        
        # Determine response HTML
        response_html = even_html if last_digit % 2 == 0 else odd_html

        return Response(response_html, mimetype='text/html'), 200
    except (ValueError, TypeError):
        return jsonify({"error": "Invalid input. Must be a number."}), 400

# @app.route("/phone", methods=["POST"])
# def phone():
#     phone_number = request.json.get("input")  # Get the input from the request JSON
#     if not phone_number:
#         return jsonify({"error": "Input is required"}), 400

#     try:
#         last_digit = int(phone_number[-1])  # Extract the last digit
        
#         # Determine if the last digit is even or odd
#         response_object = {
#                     "Registered Owner": "Akmal Bin Halim",  # Replace with actual owner information, if available
#                     "Telco Provide": "Celcom",  # Replace with actual bank info if available
#                     "Police Report": "3 Times",  # Change as needed based on your data
#                     "Result": "The account number has been flagged as potentially fraudulent activity based on reports from PDRM. Please be catious when dealing with this number."
#                 } if last_digit % 2 == 0 else {
#                     "Registered Owner": "Syafiq Jamal",  # Replace with actual owner information, if available
#                     "Telco Provide": "Maxis",  # Replace with actual bank info if available
#                     "Police Report": "0 Times",  # Change as needed based on your data
#                     "Result": "The account number has been verified and shows no fraudulent activity based on checks with Bank Negara and PDRM."
#                 }

#         return jsonify(response_object), 200
#     except (ValueError, TypeError):
#         return jsonify({"error": "Invalid input. Must be a number."}), 400

@app.route("/phone", methods=["POST"])
def phone():
    account_number = request.json.get("input")  # Get the input from the request JSON
    if not account_number:
        return jsonify({"error": "Input is required"}), 400

    try:
        last_digit = int(account_number[-1])  # Extract the last digit
        
        # HTML for even and odd cases
        even_html = """
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Fraudulent Account Warning</title>
            <style>
                body { font-family: Arial, sans-serif; background-color: #f5f5f5; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
                .container { background-color: #ffdd44; border-radius: 10px; width: 350px; padding: 20px; box-shadow: 0 4px 8px rgba(0, 0, 0, 0.2); }
                .header { font-size: 14px; text-align: left; }
                .header p { margin: 5px; font-size: 14px; }
                .content { margin-top: 20px; padding: 15px; background-color: #fff2b3; border-radius: 10px; text-align: left; }
                .content p { margin: 10px 0; font-size: 14px; }
                .robot { display: block; padding-top: 10px; padding-bottom: 10px; width: 200px; height: auto; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <p><strong>Owner:</strong> Akmal Bin Halim</p>
                    <p><strong>Telco Provider:</strong> Celcom</p>
                    <p><strong>Police Report:</strong> 3 Times</p>
                </div>
                <div class="content">
                    <p>The phone number has been flagged as potentially fraudulent activity based on reports from PDRM. </p>
                    <p><strong>Recommended:</strong> Please be catious when dealing with this number.</p>
                    <img src="robot.png" alt="Robot" class="robot">
                </div>
            </div>
        </body>
        </html>
        """
        
        odd_html = """
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Fraudulent Account Warning</title>
            <style>
                body { font-family: Arial, sans-serif; background-color: #f5f5f5; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
                .container { background-color: #ffdd44; border-radius: 10px; width: 350px; padding: 20px; box-shadow: 0 4px 8px rgba(0, 0, 0, 0.2); }
                .header { font-size: 14px; text-align: left; }
                .header p { margin: 5px; font-size: 14px; }
                .content { margin-top: 20px; padding: 15px; background-color: #fff2b3; border-radius: 10px; text-align: left; }
                .content p { margin: 10px 0; font-size: 14px; }
                .robot { display: block; padding-top: 10px; padding-bottom: 10px; width: 200px; height: auto; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <p><strong>Owner:</strong> Syafiq Jamal</p>
                    <p><strong>Telco Provider:</strong> Maxis</p>
                    <p><strong>Police Report:</strong> 0 Times</p>
                </div>
                <div class="content">
                    <p>The phone number has been verified and shows no fraudulent activity based on checks with Bank Negara and PDRM. </p>
                    <img src="robot.png" alt="Robot" class="robot">
                </div>
            </div>
        </body>
        </html>
        """
        
        # Determine response HTML
        response_html = even_html if last_digit % 2 == 0 else odd_html

        return Response(response_html, mimetype='text/html'), 200
    except (ValueError, TypeError):
        return jsonify({"error": "Invalid input. Must be a number."}), 400




@app.route("/image", methods=["POST"])
def image():

    print("Request received")
    print(request.files)

    if 'image' not in request.files:
        return jsonify({"error": "No image part"}), 400

    image = request.files['image']

    if image.filename == '':
        return jsonify({"error": "No selected image"}), 400
    # For testing, use a local image file path instead of the image uploaded by the user
    image_path = "screenshot.jpeg"  # Replace with your local image path for testing
    
    if not os.path.exists(image_path):
        return jsonify({"error": "Image file not found at the specified path"}), 400

    # Path to your local image
    img_path = "screenshot2.jpeg"

    # image_path = os.path.join("uploads", image.filename)  # Save to an 'uploads' folder
    # image.save(image_path)

    # Extract text from the local image
    img = Image.open(img_path)
    extracted_text = pytesseract.image_to_string(img)

    print("sini:",extracted_text)
    try:
            completion = openai.chat.completions.create(
                model="gpt-4",
                messages=[
                    {"role": "system",
                    "content": [
                        {
                            "type": "text",
                            "text": 
                            """Help Malaysians understand and identify fraud-related issues by providing clear 
                               insights and practical advice on how to recognize, report, and prevent fraud in everyday situations, 
                               especially related to banking and online scams. The user input will be from a 
                               image to text converter, analyze the text and give your analysis whether this is a possible fraud or not.

                                        
                                        your prompt should be:
                                        - Precise
                                        - Break into 5 category, Type of upload, Risk, Possible Scam, Percentage Scam and Analysis
                                        - Type of upload either email or whatsapp
                                        - Risk should be either None, Low, Medium and High
                                        - Possible Scam is explaining the types of scams in less than 5 words
                                        - Percenatge Scam is the value from either 0% to 100%
                                        - Analysis of the possible fraud in less than 30 words
                                        - If text in malay reply in malay, vise versa for english
                                        - Every age group can understand
                                        - Don't say things that are not related
                                        - Less than 40 word
                            """
                        }
                    ]},
                    {
                        "role": "user",
                        "content": [{
                            "type": "text",
                            "text": extracted_text
                        }]
                    }
                ]
            )
            response_text = completion.choices[0].message.content
            return jsonify({"response": response_text}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

# Run the Flask app
if __name__ == "__main__":
    app.run(debug=True,)
 