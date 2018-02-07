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

mt = require 'margin_trading' # import margin trading module 
talib = require 'talib'  # import technical indicators library (https://cryptotrader.org/talib)

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
      endIdx: high.length - lag
      optInTimePeriod: period
     _.last(results)

#### Init
init: ->
    
    context.verbose = true
    context.live = true
    context.marginFactor = 0.8
    context.trailingStopPercent = 0.07
    
    context.sarAccel = 0.005
    context.sarAccelmax = 0.05
    context.sarAccelShort = 0.005
    context.sarAccelmaxShort = 0.05
    context.lag = 1
    context.period = 20
    context.adxLimit = 15
    
    context.invested = false 
    context.positionStatus = "start"
    context.priceRef = 0

    setPlotOptions
        close:
            color: 'black'
            secondary: true
            size: 10
        performance:
            color: 'blue'
            secondary: true
            size: 5
        sarLong:
            color: 'green'
            size: 5
        sarShort:
            color: 'red'
            size: 5
        stopOrder:
            color: 'orange'
            size: 5
        stopOrderFilled:
            color: 'yellow'
            size: 10
            
#### Tick execution
handle: ->

    instrument =  data.instruments[0]
    currentPrice = instrument.price #current price
    storage.startPrice ?= instrument.price #initial price
    storage.coin ?= instrument.pair.substring(0, 3).toUpperCase() #coin name

    marginInfo = mt.getMarginInfo instrument
    currentBalance = marginInfo.margin_balance #current margin balance
    tradeableBalance = marginInfo.tradable_balance #current tradeable margin balance
    storage.startBalance ?= marginInfo.margin_balance  #initial margin balance

    lastTotalProfitPercent = (currentBalance / storage.startBalance - 1) * 100 #Profit vor aktuellem Trade
 
    sarLong = functions.sar(instrument.high, instrument.low, 1,context.sarAccel, context.sarAccelmax) 
    sarShort = functions.sar(instrument.high, instrument.low, 1,context.sarAccelShort, context.sarAccelmaxShort)
    adx = functions.adx(instrument.high, instrument.low, instrument.close,context.lag, context.period) 

    plotMark
        sarShort: sarShort
        sarLong: sarLong
 
    if context.stopOrder
        debug "STOP ORDER______: ##{context.stopOrder.id}"
        if context.stopOrder.filled
            if context.positionStatus == "long"
                context.positionStatus = "wait for short"
            if context.positionStatus == "short"
                context.positionStatus = "wait for long"
            context.invested = false
            debug "STOP ORDER______: ##{context.stopOrder.id} (FILLED)"
    else
        debug "STOP ORDER______: NOT ACTIVE" 


##### Logging

    debug "STATUS__________: #{context.positionStatus}"
    debug "INVESTED________: #{context.invested}"
    debug "ADX_____________: #{adx}"
    debug "CURRENT PRICE___: #{currentPrice.toFixed(2)} USD"
    debug "CURRENT BALANCE_: #{currentBalance.toFixed(2)} USD"
    debug "START BALANCE___: #{storage.startBalance.toFixed(2)} USD"

    debug "BOT PROFIT______: #{lastTotalProfitPercent.toFixed(2)}% (w/o current position!)"
    debug "B&H PROFIT______: #{((currentPrice / storage.startPrice - 1) *  100).toFixed(2)}%"  

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

        plot
            performance: curProfitPercentTotal

        debug "--------------------------------------------------------"
        if curPosAmount > 0
            info "LONG POSITION___________: #{curPosAmount} #{storage.coin} @ #{curPosPrice.toFixed(2)} USD"
        else     
            warn "SHORT POSITION__________: #{curPosAmount} #{storage.coin} @ #{curPosPrice.toFixed(2)} USD"                
        debug "CURRENT POS BALANCE____: #{curPosBalance.toFixed(2)} USD"
        debug "START POS BALANCE______: #{curPosBalanceAtStart.toFixed(2)} USD"
        debug "PROFIT POSITION________: #{curPosProfit.toFixed(2)} USD (#{curPosProfitPercent.toFixed(2)}%)"
        debug "PROFIT TOTAL___________: #{curBalanceTotal.toFixed(2)} USD (#{curProfitPercentTotal.toFixed(2)}%)"
        debug "CURRENT MARGIN BALANCE_: #{@functions.OpenPositionCurrentBalance(instrument.price, storage.startBalance, currentPosition).toFixed(2)}"

##### state machine
  
    switch context.positionStatus
        when "start"
            if (sarLong < instrument.price) && adx > context.adxLimit #long
                context.positionStatus = "long"
                break
        when "long"
            if instrument.price >= context.priceRef && currentPosition && instrument.price > curPosPrice && curPosProfitPercent > 5
                mt.cancelOrder(context.stopOrder)
                context.stopOrder = mt.addOrder 
                    instrument: instrument
                    side: 'sell'
                    type: 'stop'
                    amount: curPosAmount
                    price: currentPrice * (1 - context.trailingStopPercent)
                    warn "STOP ORDER UPDATE______: #{currentPrice * (1 - context.trailingStopPercent)}"
                    plotMark
                        stopOrder: currentPrice * (1 - context.trailingStopPercent)
                    
            if currentPrice > context.priceRef
                context.priceRef = currentPrice
            if (sarLong > instrument.price) #short
                context.positionStatus = "wait for short"
                closePosition = true
                break
        when "short"
            if instrument.price <= context.priceRef && currentPosition && instrument.price < curPosPrice && curPosProfitPercent > 5
                mt.cancelOrder(context.stopOrder)
                context.stopOrder = mt.addOrder 
                    instrument: instrument
                    side: 'buy'
                    type: 'stop'
                    amount: Math.abs(curPosAmount)
                    price: currentPrice * (1 + context.trailingStopPercent)
                    warn "STOP ORDER UPDATE______: #{currentPrice * (1 + context.trailingStopPercent)}"
                    plotMark
                        stopOrder: currentPrice * (1 + context.trailingStopPercent)
            if currentPrice < context.priceRef
                context.priceRef = currentPrice
            if (sarShort < instrument.price) #long
                context.positionStatus = "wait for long"
                closePosition = true
                break
        when "wait for long"
            if (sarLong < instrument.price) && adx > context.adxLimit
                context.positionStatus = "long"
        when "wait for short"
            if (sarShort > instrument.price) && adx > context.adxLimit
                context.positionStatus = "short"

#### Trading

######## CLOSING 
    
    if closePosition
        if currentPosition
            warn "CLOSING POSITION"
            mt.closePosition instrument
            mt.cancelOrder(context.stopOrder)
            marginInfo = mt.getMarginInfo instrument #update margin info after close
            context.invested = false
            closePosition = false

            if curPosProfit >= 0
                info "Juhuu, du hast eben #{curPosProfit.toFixed(2)} USD (#{curPosProfitPercent.toFixed(2)}%) verdient!"
                sendSMS "Juhuu, du hast eben #{curPosProfit.toFixed(2)} USD (#{curPosProfitPercent.toFixed(2)}%) verdient!"
            else
                warn "Shit, du hast eben #{curPosProfit.toFixed(2)} USD (#{curPosProfitPercent.toFixed(2)}%) verloren"
                sendSMS "Shit, du hast eben #{curPosProfit.toFixed(2)} USD (#{curPosProfitPercent.toFixed(2)}%) verloren"                

            plotMark
                close: curProfitPercentTotal

######## LONG 

    investableCash = (marginInfo.tradable_balance / currentPrice) * context.marginFactor

    if  context.positionStatus == "long" 
        unless context.invested
            # open long position
           mt.addOrder
                instrument: instrument
                side: 'buy'
                type: 'limit'
                amount: investableCash
                price: currentPrice
            info "Fee: #{((investableCash * currentPrice) * 0.002).toFixed(2)}"
            context.invested = true
            context.stopOrder = mt.addOrder 
                instrument: instrument
                side: 'sell'
                type: 'stop'
                amount: investableCash
                price: currentPrice * (1 - (context.trailingStopPercent * 2))
            plotMark
                stopOrder: currentPrice * (1 - (context.trailingStopPercent * 2))
            context.priceRef = instrument.price

######## SHORT

    if context.positionStatus == "short"
        unless context.invested
            # open short position
            mt.addOrder
                instrument: instrument
                side: 'sell'
                type: 'limit'
                amount: investableCash
                price: currentPrice
            context.invested = true
            context.stopOrder = mt.addOrder 
                instrument: instrument
                side: 'buy'
                type: 'stop'
                amount: investableCash
                price: currentPrice * (1 + (context.trailingStopPercent * 2))
            plotMark
                stopOrder: currentPrice * (1 + (context.trailingStopPercent * 2))
            context.priceRef = instrument.price

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