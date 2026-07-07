import yfinance as yf
ticker = yf.Ticker("SPCX")
hist = ticker.history(period="2d")
print("Hist:", hist)
