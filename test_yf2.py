import yfinance as yf
ticker = yf.Ticker("SPCX")
df = ticker.history(period="1d", interval="5m")
print("DF length:", len(df))
if len(df) == 0:
    print(df)
