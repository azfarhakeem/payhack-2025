import openai

openai.api_key = "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"

completion = openai.ChatCompletion.create(
    model="gpt-4",
    messages=[
        {"role": "system", "content": "You're a helpful assistant."},
        {"role": "user", "content": "Are semicolons optional in JavaScript?"}
    ]
)

print("Response:", completion['choices'][0]['message']['content'])
