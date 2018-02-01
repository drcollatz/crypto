#### Copyright Paules
#### Collbot

#### ToDos

# - bei 'live' Bots verbose automatisch aktivieren
# - beim start checken ob bereits eine Position offen ist und evtl. invested=true setzen
# - Programmablauf / logging etc neu sortieren
# - First Position Strategie? Warten bis zum nächsten Wechsel, oder direkt loslegen?
# - Fees berechnen (0.2 % von komplettem Kauf- oder Verkaufswert)

# Idee: Ultra Fast Bot 1Min-5Min Ticks... Pro Tag nur wenige aber dafür super safe trades "1% und gut" (bei margin sogar nur 0.4% nötig) -> 30% im Monat.

#### START

trading = require 'trading' # import core trading module
talib = require 'talib'  # import technical indicators library (https://cryptotrader.org/talib)

_maximumExchangeFee = .20# params.add "Maximum exchange fee %", .25
_maximumOrderAmount = 1 #params.add "Maximum order amount", 1
_orderTimeout = 30 #params.add "Order timeout", 30

class functions

#### TA-lib Indicatots 

  @sar: (high, low, lag, accel, accelmax) ->
    results = talib.SAR
      high: high
      low: low
      startIdx: 0
      endIdx: high.length - lag
      optInAcceleration: accel
      optInMaximum: accelmax
    _.last(results) 

#### Init
init: ->
    
    context.verbose = true
    context.live = true
    context.sarAccel = 0.005
    context.sarAccelmax = 0.5
    context.sarAccelShort = 0.01
    context.sarAccelmaxShort = 0.1
    context.positionStatus = "start"
    context.buyPrice

#### Tick execution
handle: ->

    instrument =  data.instruments[0]
    
    storage.coin ?= data.instruments[0].pair.substring(0, 3).toUpperCase()

    assetsAvailable = @portfolios[instrument.market].positions[instrument.asset()].amount
    context.assetsAvailable = assetsAvailable #current assets
    storage.startAssets ?= assetsAvailable    #inital assets

    currencyAvailable = @portfolios[instrument.market].positions[instrument.curr()].amount
    context.currencyAvailable = currencyAvailable #current currency
    storage.startCurrency ?= currencyAvailable    #inital currency

    context.currentPrice = instrument.price
    storage.startPrice ?= instrument.price #inital price

    maximumBuyAmount = (currencyAvailable/instrument.price) * (1 - (_maximumExchangeFee/100))
    maximumSellAmount = (assetsAvailable * (1 - (_maximumExchangeFee/100)))

    diff = ((instrument.price / context.buyPrice - 1)*100) 


    
##### Logging

    if context.verbose
        debug "Status____________: #{context.positionStatus}"
        debug "Balance ASSETS____: #{assetsAvailable} #{storage.coin}"
        debug "Balance CURRENCY__: #{currencyAvailable} USD"
        debug "Current PRICE_____: #{instrument.price} USD"   
        debug "Current DIFF______: #{diff.toFixed(2)}%"
    
    debug "Bot Gewinn________: #{(((context.currencyAvailable + (context.assetsAvailable * context.currentPrice)) / storage.startCurrency - 1)*100).toFixed(2)}%"
    debug "B&H Gewinn________: #{((context.currentPrice / storage.startPrice - 1)*100).toFixed(2)}%"   

    sarLong = functions.sar(instrument.high, instrument.low, 1,context.sarAccel, context.sarAccelmax) 


    if (diff < -10) ||( diff > 5) && (@portfolio.positions[instrument.asset()].amount > 0) 
        context.positionStatus = "close"
        warn "EMERGENCY EXIT!"
        plotMark
            "stop": 0

    plot
        "sarLong": sarLong

    switch context.positionStatus
        when "start"
            if (sarLong < instrument.price) #long
                context.positionStatus = "long"            
                warn "LONG"
                break
        when "long"
            if (sarLong > instrument.price) && (context.buyPrice < instrument.price) #close long
                context.positionStatus = "close"
                break

#### Trading

    debug "AMOUNT: #{@portfolio.positions[instrument.asset()].amount}"

######## LONG 

    if  context.positionStatus == "long" && (@portfolio.positions[instrument.base()].amount > 0)
        # open long position
        info "KAUFEN"            
        trading.buy instrument
        context.buyPrice = instrument.price

######## CLOSE

    if context.positionStatus == "close" 
        # close long position
        context.positionStatus = "start"   
        if (@portfolio.positions[instrument.asset()].amount > 0) 
            warn "VERKAUFEN"
            trading.sell instrument


    if context.verbose
        debug "######################################################## "

onRestart: ->
    warn "RESTART DETECTED!!!"

onStop: ->
   
    debug "######## BOT ENDE ########"
    debug "Start currency was__: #{storage.startCurrency} USD"
    debug "End currency is_____: #{context.currencyAvailable} USD"
    debug "Start asset was_____: #{storage.startAssets} #{storage.coin}"
    debug "End asset is________: #{context.assetsAvailable} #{storage.coin}"
    debug "Bot Gewinn__________: #{(((context.currencyAvailable + (context.assetsAvailable * context.currentPrice)) / storage.startCurrency - 1)*100).toFixed(2)}%"
    debug "B&H Gewinn__________: #{((context.currentPrice / storage.startPrice - 1)*100).toFixed(2)}%" 