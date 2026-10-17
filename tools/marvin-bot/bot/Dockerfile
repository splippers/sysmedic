FROM python:3.12-slim
RUN pip install --no-cache-dir discord.py==2.4.0 requests==2.32.3
COPY bot.py /app/bot.py
USER 10001
CMD ["python", "/app/bot.py"]
