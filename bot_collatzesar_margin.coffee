#### Copyright Paules
#### Collbot

#### ToDos

# - beim start checken ob bereits eine Position offen ist und evtl. invested=true setzen
# - Programmablauf / logging etc neu sortieren
# - Fees berechnen (0.2 % von komplettem Kauf- oder Verkaufswert)

#### START

mt = require 'margin_trading' # import margin trading module 
talib = require 'talib'  # import technical indicators library (https://cryptotrader.org/talib)
ds  = require 'datasources'

ds.add 'bitfinex', 'btc_usd', '30m', 500

class functions

  @OpenPositionPL: (currentPrice, marginPosition) ->
        pl = ((currentPrice - marginPosition.price)/marginPosition.price) * 100
        if (marginPosition.amount < 0)
            return -pl
        else
            return pl

  @OpenPositionCurrentBalance: (currentPrice, startingBalance, marginPosition) ->
        return (startingBalance + marginPosition.amount * (currentPrice - marginPosition.price))

  @sar: (high, low, lag, accel, accelmax) ->
    results = talib.SAR
      high: high
      low: low
      startIdx: 0
      endIdx: high.length - lag
      optInAcceleration: accel
      optInMaximum: accelmax
    _.last(results) 
    
  @adx: (high, low, close, lag, period) ->
    results = talib.ADX
      high: high
      low: low
      close: close
      startIdx: 0
      endIdx: high.length - 
      lag
      optInTimePeriod: period
     _.last(results)

  @macd: (data, lag, FastPeriod,SlowPeriod,SignalPeriod) ->
    results = talib.MACD
     inReal: data
     startIdx: 0
     endIdx: data.length - lag
     optInFastPeriod: FastPeriod
     optInSlowPeriod: SlowPeriod
     optInSignalPeriod: SignalPeriod
    result =
      macd: _.last(results.outMACD)
      signal: _.last(results.outMACDSignal)
      histogram: _.last(results.outMACDHist)
    result

#### Init
init: ->
    
    context.lag = 1
    context.period = 20
    context.close 		= 1
    context.FastPeriod  = 12       
    context.SlowPeriod  = 26
    context.SignalPeriod= 9
    
    context.sarAccel = 0.02
    context.sarAccelmax = 0.02

#   context.adxLimit = 25
#   context.histoLimit = 10
 
    context.macdLimit = 30
    
    context.marginFactor = 0.9
    context.trailingStopPercent = 0.8
    context.takeProfitPercent = 0.8

    context.invested = false 
    context.locked = "unlocked"
    context.positionStatus = "start"
    context.priceRef = 0

    setPlotOptions
        performance:
            color: 'blue'
            secondary: true
            size: 5
        sarLong:
            color: 'green'
            size: 3
        sarShort:
            color: 'red'
            size: 3
        SL:
            color: 'black'
            size: 5
        TP:
            color: 'Chartreuse'
            size: 5
        macd:
            color: 'DarkOrange'
            secondary: true
            size: 2
        macd_limit:
            color: 'red'
            secondary: true
            size: 4
            
#### Tick execution
handle: ->

    btc_30m = ds.get 'bitfinex', 'btc_usd', '30m'
    instrument =  data.instruments[0]
    instrument_30m = data.instruments[1]
    storage.coin ?= instrument.pair.substring(0, 3).toUpperCase() #coin name    
  
    currentPrice = instrument.price #current price

    storage.startPrice ?= instrument.price #initial price

    marginInfo = mt.getMarginInfo instrument
    currentBalance = marginInfo.margin_balance #current margin balance
    tradeableBalance = marginInfo.tradable_balance #current tradeable margin balance
    storage.startBalance ?= marginInfo.margin_balance  #initial margin balance

    lastTotalProfitPercent = (currentBalance / storage.startBalance - 1) * 100 #Profit vor aktuellem Trade
 
#    sar = functions.sar(instrument.high, instrument.low, 1,context.sarAccel, context.sarAccelmax) 
    sar_30m = functions.sar(instrument_30m.high, instrument_30m.low, 1,context.sarAccel, context.sarAccelmax) 
    macd = functions.macd(instrument.close,context.lag,context.FastPeriod,context.SlowPeriod,context.SignalPeriod)
    adx = functions.adx(instrument.high, instrument.low, instrument.close,context.lag, context.period) 

    if sar_30m > currentPrice
        info "BEARISH"
        if context.locked == "long"
            context.locked = "unlocked"
        plotMark
            sarShort: sar_30m
    else
        if context.locked == "short"
            context.locked = "unlocked"
        info "BULLISH"
        plotMark
            sarLong: sar_30m  

    if macd.macd > context.macdLimit || macd.macd < -context.macdLimit
        plotMark
            macd_limit: macd.macd
    else
        plotMark
            macd: macd.macd
    
##### Logging

    info "STATUS__________: #{context.positionStatus} / INVESTED?: #{context.invested} / LOCKED?: #{context.locked}"
    debug "CURRENT PRICE___: #{currentPrice.toFixed(2)} USD"
    debug "INDICATORS______: MACD: #{macd.macd.toFixed(2)} / HISTO: #{macd.histogram.toFixed(2)} / ADX: #{adx.toFixed(2)} / SAR: #{sar_30m.toFixed(2)}"
    debug "SETTINGS________: TS: #{context.trailingStopPercent}% / TP: #{context.takeProfitPercent}% / MACD LIMIT: #{context.macdLimit}"  
    debug "CURRENT BALANCE_: #{currentBalance.toFixed(2)} USD (START: #{storage.startBalance.toFixed(2)} USD)"
    info "PROFIT__________: BOT: #{lastTotalProfitPercent.toFixed(2)}% / B&H: #{((currentPrice / storage.startPrice - 1) *  100).toFixed(2)}%"
 
##### Postition

    currentPosition = mt.getPosition instrument

    if currentPosition
        context.invested = true
        curPosAmount = currentPosition.amount
        curPosPrice = currentPosition.price
        curPosBalanceAtStart = curPosAmount * curPosPrice
        curPosBalance = curPosAmount * currentPrice
        curPosProfit = curPosBalance - curPosBalanceAtStart
        curPosProfitPercent = @functions.OpenPositionPL(instrument.price, currentPosition)
        curBalanceTotal = currentBalance + curPosProfit - storage.startBalance
        curProfitPercentTotal = ((currentBalance + curPosProfit) / storage.startBalance - 1) * 100

        if !context.stopOrder
            warn "ACHTUNG kein STOP LOSS AKTIV"

            if context.positionStatus == "long"
                context.stopOrder = mt.addOrder 
                    instrument: instrument
                    side: 'sell'
                    type: 'stop'
                    amount: Math.abs(currentPosition.amount)
                    price: currentPosition.price * (1 - (context.trailingStopPercent / 100))
                plotMark
                    SL: currentPosition.price * (1 - (context.trailingStopPercent / 100))

            if context.positionStatus == "short"    
                context.stopOrder = mt.addOrder 
                    instrument: instrument
                    side: 'buy'
                    type: 'stop'
                    amount: Math.abs(currentPosition.amount)
                    price: currentPosition.price * (1 + (context.trailingStopPercent / 100))
                plotMark
                    SL: currentPosition.price * (1 + (context.trailingStopPercent / 100))

        if !context.takeProfitOrder
            warn "ACHTUNG kein TAKE PROFIT AKTIV"

            if context.positionStatus == "long" && (currentPosition.price * (1 + (context.takeProfitPercent / 100))) > currentPrice 
                context.takeProfitOrder = mt.addOrder
                    instrument: instrument
                    side: 'sell'
                    type: 'limit'
                    amount: Math.abs(currentPosition.amount)
                    price: currentPosition.price * (1 + (context.takeProfitPercent / 100))
                plotMark
                    TP: currentPosition.price * (1 + (context.takeProfitPercent / 100))
  
            
            if context.positionStatus == "short" && currentPosition.price * (1 - (context.takeProfitPercent / 100)) < currentPrice   
                context.takeProfitOrder = mt.addOrder
                    instrument: instrument
                    side: 'buy'
                    type: 'limit'
                    amount: Math.abs(currentPosition.amount)
                    price: currentPosition.price * (1 - (context.takeProfitPercent / 100))
                plotMark
                    TP: currentPosition.price * (1 - (context.takeProfitPercent / 100))
            
        plot
            performance: curProfitPercentTotal

        debug "--------------------------------------------------------"
        if curPosAmount > 0
            info "LONG POSITION___________: #{curPosAmount} #{storage.coin} @ #{currentPosition.price.toFixed(2)} USD"
        else     
            warn "SHORT POSITION__________: #{curPosAmount} #{storage.coin} @ #{currentPosition.price.toFixed(2)} USD"                
        
        debug "CURRENT POS BALANCE____: #{curPosBalance.toFixed(2)} USD"
        debug "START POS BALANCE______: #{curPosBalanceAtStart.toFixed(2)} USD"
        debug "PROFIT POSITION________: #{curPosProfit.toFixed(2)} USD (#{curPosProfitPercent.toFixed(2)}%)"
        debug "PROFIT TOTAL___________: #{curBalanceTotal.toFixed(2)} USD (#{curProfitPercentTotal.toFixed(2)}%)"
        debug "CURRENT MARGIN BALANCE_: #{@functions.OpenPositionCurrentBalance(instrument.price, storage.startBalance, currentPosition).toFixed(2)}"
    else
        info "KEINE POSITION"

        if context.stopOrder
            debug "STOP ORDER______: ##{context.stopOrder.id}"
            if context.stopOrder.filled 
                context.positionStatus = "start"
                context.invested = false
                debug "STOP ORDER______: ##{context.stopOrder.id} (FILLED)"
                if context.takeProfitOrder
                    mt.cancelOrder(context.takeProfitOrder)
                    context.takeProfitOrder = null
                context.stopOrder = null
            else
                debug "STOP ORDER______: NOT ACTIVE" 
        
        if context.takeProfitOrder
            debug "PROF ORDER______: ##{context.takeProfitOrder.id}"
            if context.takeProfitOrder.filled 
                context.positionStatus = "start"
                context.invested = false
                debug "PROF ORDER______: ##{context.takeProfitOrder.id} (FILLED)"
                if context.stopOrder
                    mt.cancelOrder(context.stopOrder)
                    context.stopOrder = null
                context.takeProfitOrder = null
            else
                debug "PROF ORDER______: NOT ACTIVE" 

        activeOrders = []
        activeOrders = mt.getActiveOrders()
        if (activeOrders and activeOrders.length)
            for activeOrder in activeOrders
                mt.cancelOrder(activeOrder)
                warn "Restliche Order gelöscht: #{activeOrder.id}"


##### state machine
  
    switch context.positionStatus

        when "start"
            if (sar_30m < instrument.price) && context.locked == "unlocked" && macd.macd > context.macdLimit  #long
                context.positionStatus = "long"
                break
            if (sar_30m > instrument.price) && context.locked == "unlocked" && macd.macd < -context.macdLimit #short
                context.positionStatus = "short"
                break

        when "long"
            if instrument.price >= context.priceRef && currentPosition
                mt.cancelOrder(context.stopOrder)
                context.stopOrder = mt.addOrder 
                    instrument: instrument
                    side: 'sell'
                    type: 'stop'
                    amount: curPosAmount
                    price: currentPrice * (1 - context.trailingStopPercent / 100)
                    
                    warn "STOP ORDER UPDATE______: #{currentPrice * (1 - context.trailingStopPercent / 100)}"
                    plotMark
                        SL: currentPrice * (1 - context.trailingStopPercent / 100)

            if currentPrice > context.priceRef
                context.priceRef = currentPrice

            if (sar_30m > instrument.price) && context.invested == false #short
                context.positionStatus = "start"
                break

        when "short"
            if instrument.price <= context.priceRef && currentPosition
                mt.cancelOrder(context.stopOrder)
                context.stopOrder = mt.addOrder 
                    instrument: instrument
                    side: 'buy'
                    type: 'stop'
                    amount: Math.abs(curPosAmount)
                    price: currentPrice * (1 + context.trailingStopPercent / 100)

                    warn "STOP ORDER UPDATE______: #{currentPrice * (1 + context.trailingStopPercent / 100)}"
                    plotMark
                        SL: currentPrice * (1 + context.trailingStopPercent / 100)

            if currentPrice < context.priceRef
                context.priceRef = currentPrice
                
            if (sar_30m < instrument.price) && context.invested == false #long
                context.positionStatus = "start"
                break

#### Trading

######## LONG 

    investableCash = (marginInfo.tradable_balance / currentPrice) * context.marginFactor

    if context.positionStatus == "long" 
        unless context.invested
            # open long position
            if mt.buy instrument, 'market', investableCash, instrument.price
                info "LONG Position opened!"
                context.invested = true
                context.locked = "long"
            context.priceRef = currentPrice

######## SHORT

    if context.positionStatus == "short"
        unless context.invested
            # open short position
            if mt.sell instrument, 'market', investableCash, instrument.price
                info "SHORT Position opened!"
                context.invested = true
                context.locked = "short"
            context.priceRef = currentPrice

    debug "######################################################## "


onRestart: ->
    warn "RESTART DETECTED!!!"

#### ENDE

onStop: ->
    info "*********************** BOT ENDE ***********************"
    
    instrument = @data.instruments[0]
    if (currentPosition = mt.getPosition instrument) && context.live == false
        warn "CLOSING POSITION"
        mt.closePosition instrument
    
    marginInfo = mt.getMarginInfo instrument
    currentBalance = marginInfo.margin_balance #current margin balance

    debug "START BALANCE___: #{storage.startBalance.toFixed(2)} USD"
    debug "END BALANCE_____: #{currentBalance.toFixed(2)} USD"

    botProfit = ((currentBalance / storage.startBalance - 1)*100)
    buhProfit = ((instrument.price / storage.startPrice - 1)*100)
    if botProfit >= 0
        info "BOT PROFIT SUM__: #{botProfit.toFixed(2)}%"
    else
        warn "BOT PROFIT SUM__: #{botProfit.toFixed(2)}%" 
    if buhProfit >= 0
        info "B&H PROFIT SUM__: #{buhProfit.toFixed(2)}%" 
    else
        warn "B&H PROFIT SUM__: #{buhProfit.toFixed(2)}%" 