//+------------------------------------------------------------------+
//|                                   Copyright 2016, Erlon F. Souza |
//|                                       https://github.com/erlonfs |
//+------------------------------------------------------------------+

#property   copyright   "Copyright 2016, Erlon F. Souza"
#property   link        "https://github.com/erlonfs"
#define     version     "1.15.7"

#include <Trade\Trade.mqh>
#include <BadRobot.Framework\Logger.mqh>
#include <BadRobot.Framework\Account.mqh>

class BadRobot
{

	private:

	//Classes
	Logger _logger;
	Account _account;
	MqlTick _price;
	CTrade _trade;
	CPositionInfo _positionInfo;

	//Definicoes Basicas
	string _symbol;
	double _volume;
	double _spread;
	double _stopGain;
	double _stopLoss;
	string _robotName;
	string _robotVersion;

	//Enums
	ENUM_TIMEFRAMES _period;

	//Trailing Stop
	bool _isTrailingStop;
	double _trailingStopInicio;
	double _trailingStop;

	//Break Even
	bool _isBreakEven;
	bool _isBreakEvenExecuted;
	double _breakEvenInicio;
	double _breakEven;
	
	//Stop no candle anterior
	bool _isStopOnLastCandle;
	double _spreadStopOnLastCandle;
	bool _waitBreakEvenExecuted;
	bool _isPeriodCustom;
	ENUM_TIMEFRAMES _periodStopOnLastCandle;

	//Parciais
	bool _isParcial;
	double _isPrimeiraParcial;
	double _primeiraParcialVolume;
	double _primeiraParcialInicio;
	double _isSegundaParcial;
	double _segundaParcialVolume;
	double _segundaParcialInicio;
	double _isTerceiraParcial;
	double _terceiraParcialVolume;
	double _terceiraParcialInicio;

	//Gerenciamento Financeiro
	bool _isGerenciamentoFinanceiro;
	double _totalProfitMoney;
	double _totalStopLossMoney;
	double _totalOrdensVolume;
	double _maximoLucroDiario;
	double _maximoPrejuizoDiario;

	//Text
	string _lastText;
	string _lastTextValidate;
	string _lastTextInfo;

	//Period
	MqlDateTime _timeCurrent;
	MqlDateTime _horaInicio;
	MqlDateTime _horaFim;
	MqlDateTime _horaInicioIntervalo;
	MqlDateTime _horaFimIntervalo;

	//Period Interval
	string _horaInicioString;
	string _horaFimString;
	string _horaInicioIntervaloString;
	string _horaFimIntervaloString;

	//Flags
	bool _isBusy;
	bool _isNewCandle;
	bool _isNewDay;
	bool _isNotificacoesApp;
	bool _isAlertMode;
	bool _isClosePosition;
	bool _isRewrite;

	void ManagePosition()
	{

		if (_isBusy) return;

		_isBusy = true;

		if (GetPositionMagicNumber() != _trade.RequestMagic())
		{
			return;
		}

		if (_isClosePosition)
		{
			if (GetHoraFim().hour == GetTimeCurrent().hour)
			{
				if (GetHoraFim().min >= GetTimeCurrent().min)
				{
					ClosePosition();
				}
			}
		}

		if (!HasPositionLossOrPositionGain())
		{
			RepositionTrade();
			RestartManagePosition();
		}
		else
		{
			ManageStopOnLastCandle();
			ManageTrailingStop();
			ManageBreakEven();
			ManageParcial();
		}
		
		if(GetIsNewCandle())
		{
		   ManageDrawParcial();
		}

		_isBusy = false;

	}

	void RestartManagePosition()
	{
		_isPrimeiraParcial = false;
		_isSegundaParcial = false;
		_isTerceiraParcial = false;
		_isBreakEvenExecuted = false;
		
		ManageDrawParcial();
		
	}

	void ManageDealsProfit()
	{

		string CurrDate = TimeToString(TimeCurrent(), TIME_DATE);
		HistorySelect(StringToTime(CurrDate), TimeCurrent());

		ulong ticket = 0;
		double price;
		double profit;
		datetime time;
		string symbol;
		string comment;
		long type;
		long entry;
		double volume;
		ulong magic;

		double totalGainMoney = 0.0;
		double totalLossMoney = 0.0;
		double qtdOrdensVolume = 0;

		for (int i = HistoryDealsTotal() - 1; i >= 0; i--)
		{
			ticket = HistoryDealGetTicket(i);

			if (ticket <= 0)
			{
				continue;
			}

			price = HistoryDealGetDouble(ticket, DEAL_PRICE);
			time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
			symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
			comment = HistoryDealGetString(ticket, DEAL_COMMENT);
			type = HistoryDealGetInteger(ticket, DEAL_TYPE);
			magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
			entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
			profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
			volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);

			if (symbol != _symbol)
			{
				continue;
			}

			if (magic != _trade.RequestMagic())
			{
				continue;
			}

			if (!price && !time)
			{
				continue;
			}

			if (profit < 0)
			{
				totalLossMoney += profit;
				qtdOrdensVolume += volume;
				continue;
			}

			if (profit > 0)
			{
				totalGainMoney += profit;
				qtdOrdensVolume += volume;
				continue;
			}

		}

		_totalProfitMoney = totalGainMoney;
		_totalStopLossMoney = totalLossMoney;
		_totalOrdensVolume = qtdOrdensVolume;


	}

	bool ManageStopOnLastCandle()
	{	
	   if(_isBreakEven && _waitBreakEvenExecuted)
	   {
	      if(!_isBreakEvenExecuted) return false;
	   }

		if (!_isStopOnLastCandle || !_isNewCandle)
		{		   
			return false;
		}

		MqlRates _rates[];

		if (CopyRates(GetSymbol(), _isPeriodCustom ? _periodStopOnLastCandle : GetPeriod(), 0, 2, _rates) <= 0)
		{
			return false;
		}

		//Posicao menor é o mais longe, ou seja, _rates[0] é o primeiro e _rates[1] é o ultimo
		MqlRates _candleAnterior = _rates[0];

		if (GetPositionType() == POSITION_TYPE_BUY)
		{

			if (GetPositionLoss() < _candleAnterior.low - GetSpreadStopOnLastCandle())
			{
				_trade.PositionModify(_symbol, _candleAnterior.low - GetSpreadStopOnLastCandle(), GetPositionGain());
				_logger.Log("Stop ajustado candle anterior. " + (string)GetPositionLoss());
				return true;
			}

		}

		if (GetPositionType() == POSITION_TYPE_SELL)
		{

			if (GetPositionLoss() > _candleAnterior.high + GetSpreadStopOnLastCandle())
			{
				_trade.PositionModify(_symbol, _candleAnterior.high + GetSpreadStopOnLastCandle(), GetPositionGain());
				_logger.Log("Stop ajustado candle anterior. " + (string)GetPositionLoss());
				return true;
			}

		}

		return false;

	}

	bool ManageTrailingStop()
	{

		if (!_isTrailingStop)
		{
			return false;
		}

		if (GetPositionType() == POSITION_TYPE_BUY)
		{

			if (GetPrice().last - GetPositionLoss() >= GetStopLoss() + _trailingStopInicio)
			{
				_trade.PositionModify(_symbol, GetPositionLoss() + _trailingStop, GetPositionGain());
				_logger.Log("Stop ajustado trailing stop. " + (string)GetPositionLoss());
				return true;
			}

		}

		if (GetPositionType() == POSITION_TYPE_SELL)
		{

			if (GetPositionLoss() - GetPrice().last >= GetStopLoss() + _trailingStopInicio)
			{
				_trade.PositionModify(_symbol, GetPositionLoss() - _trailingStop, GetPositionGain());
				_logger.Log("Stop ajustado trailing stop. " + (string)GetPositionLoss());
				return true;
			}

		}

		return false;

	}

	bool ManageBreakEven()
	{

		if (!_isBreakEven || _isBreakEvenExecuted)
		{
			return false;
		}

		if (GetPositionType() == POSITION_TYPE_BUY)
		{

			if (GetPrice().last >= GetPositionPriceOpen() + _breakEvenInicio && GetPositionLoss() < GetPositionPriceOpen())
			{
				_trade.PositionModify(_symbol, GetPositionPriceOpen() + _breakEven, GetPositionGain());
				_logger.Log("Stop ajustado break even. " + (string)(GetPositionPriceOpen() + _breakEven));
				_isBreakEvenExecuted = true;
			}
		}

		if (GetPositionType() == POSITION_TYPE_SELL)
		{

			if (GetPrice().last <= GetPositionPriceOpen() - _breakEvenInicio && GetPositionLoss() > GetPositionPriceOpen())
			{
				_trade.PositionModify(_symbol, GetPositionPriceOpen() - _breakEven, GetPositionGain());
				_logger.Log("Stop ajustado break even. " + (string)(GetPositionPriceOpen() - _breakEven));
				_isBreakEvenExecuted = true;
			}
		}

		return _isBreakEvenExecuted;

	}

	bool ManageParcial()
	{
		if (!_isParcial)
		{
			return false;
		}
		
		if(GetPrice().last <= 0) return false;

		double positionLoss = GetPositionLoss();
		double positionGain = GetPositionGain();

		bool isPrimeiraParcial = false;
		bool isSegundaParcial = false;
		bool isTerceiraParcial = false;	

		if (GetPositionType() == POSITION_TYPE_BUY)
		{

			isPrimeiraParcial = GetPrice().last >= GetPositionPriceOpen() + _primeiraParcialInicio;
			isSegundaParcial = GetPrice().last >= GetPositionPriceOpen() + _segundaParcialInicio;
			isTerceiraParcial = GetPrice().last >= GetPositionPriceOpen() + _terceiraParcialInicio;

			if (isPrimeiraParcial && !_isPrimeiraParcial && _primeiraParcialInicio > 0)
			{
				_isPrimeiraParcial = true;
				_trade.Sell(_primeiraParcialVolume, _symbol);
				_logger.Log("Saída parcial em " + (string)GetPrice().last + " com volume " + (string)_primeiraParcialVolume);
				return true;
			}

			if (isSegundaParcial && !_isSegundaParcial && _segundaParcialInicio > 0)
			{
				_isSegundaParcial = true;
				_trade.Sell(_segundaParcialVolume, _symbol);
				_logger.Log("Saída parcial em " + (string)GetPrice().last + " com volume " + (string)_segundaParcialVolume);
				return true;
			}

			if (isTerceiraParcial && !_isTerceiraParcial && _terceiraParcialInicio > 0)
			{
				_isTerceiraParcial = true;
				_trade.Sell(_terceiraParcialVolume, _symbol);
				_logger.Log("Saída parcial em " + (string)GetPrice().last + " com volume " + (string)_terceiraParcialVolume);
				return true;
			}

		}

		if (GetPositionType() == POSITION_TYPE_SELL)
		{

			isPrimeiraParcial = GetPrice().last <= GetPositionPriceOpen() - _primeiraParcialInicio;
			isSegundaParcial = GetPrice().last <= GetPositionPriceOpen() - _segundaParcialInicio;
			isTerceiraParcial = GetPrice().last <= GetPositionPriceOpen() - _terceiraParcialInicio;

			if (isPrimeiraParcial && !_isPrimeiraParcial && _primeiraParcialInicio > 0)
			{
				_isPrimeiraParcial = true;
				_trade.Buy(_primeiraParcialVolume, _symbol);
				_logger.Log("Saída parcial em " + (string)GetPrice().last + " com volume " + (string)_primeiraParcialVolume);
				return true;
			}

			if (isSegundaParcial && !_isSegundaParcial && _segundaParcialInicio > 0)
			{
				_isSegundaParcial = true;
				_trade.Buy(_segundaParcialVolume, _symbol);
				_logger.Log("Saída parcial em " + (string)GetPrice().last + " com volume " + (string)_segundaParcialVolume);
				return true;
			}

			if (isTerceiraParcial && !_isTerceiraParcial && _terceiraParcialInicio > 0)
			{
				_isTerceiraParcial = true;
				_trade.Buy(_terceiraParcialVolume, _symbol);
				_logger.Log("Saída parcial em " + (string)GetPrice().last + " com volume " + (string)_terceiraParcialVolume);
				return true;
			}

		}

		return false;
	}

	void ManageDrawParcial()
	{

		if (!_isParcial)
		{
			return;
		}
		
		string objNamePrimeiraParcial = "PRIMEIRA_PARCIAL";
		string objNameSegundaParcial = "SEGUNDA_PARCIAL";
		string objNameTerceiraParcial = "TERCEIRA_PARCIAL";

		ClearDrawParcial(objNamePrimeiraParcial);
		ClearDrawParcial(objNameSegundaParcial);
		ClearDrawParcial(objNameTerceiraParcial);

		if (!HasPositionOpen()) return;

		if (GetPositionType() == POSITION_TYPE_BUY)
		{

			if (!_isPrimeiraParcial && _primeiraParcialInicio > 0)
			{
				DrawParcial(objNamePrimeiraParcial, GetPositionPriceOpen() + _primeiraParcialInicio, 
				"Saída parcial\nPreço " + (string)(GetPositionPriceOpen() + _primeiraParcialInicio) + "\nVolume " + (string)_primeiraParcialVolume);
			}

			if (!_isSegundaParcial && _segundaParcialInicio > 0)
			{
				DrawParcial(objNameSegundaParcial, GetPositionPriceOpen() + _segundaParcialInicio, 
				"Saída parcial\nPreço " + (string)(GetPositionPriceOpen() + _segundaParcialInicio) + "\nVolume " + (string)_segundaParcialVolume);
			}

			if (!_isTerceiraParcial && _terceiraParcialInicio > 0)
			{
				DrawParcial(objNameTerceiraParcial, GetPositionPriceOpen() + _terceiraParcialInicio, 
				"Saída parcial\nPreço " + (string)(GetPositionPriceOpen() + _terceiraParcialInicio) + "\nVolume " + (string)_terceiraParcialVolume);
			}

			return;

		}

		if (GetPositionType() == POSITION_TYPE_SELL)
		{

			if (!_isPrimeiraParcial && _primeiraParcialInicio > 0)
			{
				DrawParcial(objNamePrimeiraParcial, GetPositionPriceOpen() - _primeiraParcialInicio, 
				"Saída parcial\nPreço " + (string)(GetPositionPriceOpen() - _primeiraParcialInicio) + "\nVolume " + (string)_primeiraParcialVolume);
			}

			if (!_isSegundaParcial && _segundaParcialInicio > 0)
			{
				DrawParcial(objNameSegundaParcial, GetPositionPriceOpen() - _segundaParcialInicio, 
				"Saída parcial\nPreço " + (string)(GetPositionPriceOpen() - _segundaParcialInicio) + "\nVolume " + (string)_segundaParcialVolume);
			}

			if (!_isTerceiraParcial && _terceiraParcialInicio > 0)
			{
				DrawParcial(objNameTerceiraParcial, GetPositionPriceOpen() - _terceiraParcialInicio, 
				"Saída parcial\nPreço " + (string)(GetPositionPriceOpen() - _terceiraParcialInicio) + "\nVolume " + (string)_terceiraParcialVolume);
			}

			return;

		}

	}

	void DrawParcial(string objName, double price, string text)
	{
		ObjectCreate(0, objName, OBJ_HLINE, 0, 0, price);
		ObjectSetInteger(0, objName, OBJPROP_COLOR, clrOrange);
		ObjectSetInteger(0, objName, OBJPROP_BORDER_COLOR, clrBlack);
		ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_DASHDOT);
		ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
		ObjectSetString(0, objName, OBJPROP_TOOLTIP, text);
		ObjectSetInteger(0, objName, OBJPROP_BACK, false);
		ObjectSetInteger(0, objName, OBJPROP_FILL, true);		
	}

	void ClearDrawParcial(string objName)
	{
		ObjectDelete(0, objName);
	}

	bool RepositionTrade()
	{

		if (!HasPositionOpen()) return false;

		double price = GetPositionPriceOpen();

		if (GetPositionType() == POSITION_TYPE_BUY)
		{

			double stopGain = NormalizeDouble((price + GetStopGain()), _Digits);
			double stopLoss = NormalizeDouble((price - GetStopLoss()), _Digits);

			_trade.PositionModify(_symbol, stopLoss, stopGain);

		}
		else
		{
			if (GetPositionType() == POSITION_TYPE_SELL)
			{

				double stopGain = NormalizeDouble((price - GetStopGain()), _Digits);
				double stopLoss = NormalizeDouble((price + GetStopLoss()), _Digits);

				_trade.PositionModify(_symbol, stopLoss, stopGain);

			}
		}

		_logger.Log("Stop, Gain e gerenciamento retomado");

		return true;

	}

	bool SetIsNewCandle()
	{

		static datetime OldTime;
		datetime NewTime[1];
		bool newBar = false;

		int copied = CopyTime(_symbol, _period, 0, 1, NewTime);

		if (copied > 0 && OldTime != NewTime[0])
		{
			newBar = true;
			OldTime = NewTime[0];
		}

		return (newBar);

	}

	bool SetIsNewday()
	{

		static int oldDay;
		int newDay = GetTimeCurrent().day;
		bool isNewDay = false;

		if (oldDay != newDay)
		{
			isNewDay = true;
			oldDay = newDay;
			_logger.Log("Seja bem vindo ao " + _robotName);
		}

		return (isNewDay);

	}
	
	void ShowInfo()
	{					
		if(!_isRewrite) return;

		Comment("--------------------------------------" +
			"\n" + GetRobotName() + " " + ToPeriodText(_period) + " " + GetRobotVersion() + "\nFRAMEWORK " + version +
			(_lastTextInfo != NULL ? "\n--------------------------------------\n" + _lastTextInfo : "") +
			
			(!_isAlertMode ?
			   "\n--------------------------------------" +
   			"\nVOLUME ATUAL " + (HasPositionOpen() ? (GetPositionType() == POSITION_TYPE_SELL ? "-" : "") + (string)GetPositionVolume() : "0") +
   			"\nTP " + DoubleToString(_stopGain, _Digits) + " SL " + DoubleToString(_stopLoss, _Digits)
   			: "\nMODO ALERTA ATIVADO"
			) + "\n--------------------------------------" +
			
			(_isStopOnLastCandle ? "\nSTOP CANDLE ANTERIOR " + ToPeriodText(_periodStopOnLastCandle) : "") +
			
			(_isTrailingStop ? "\nTRAILING STOP " + (string)(GetPositionType() == POSITION_TYPE_SELL ? 
			                                                 GetPositionPriceOpen() - _trailingStopInicio : 
			                                                 GetPositionPriceOpen() + _trailingStopInicio) + " " + DoubleToString(_trailingStop, _Digits) : "") +
			                                                 
			(_isBreakEven ? "\nBREAK EVEN " + (_isBreakEvenExecuted ? "" : (string)(GetPositionType() == POSITION_TYPE_SELL ? 
			                                                                        GetPositionPriceOpen() - _breakEven :
			                                                                        GetPositionPriceOpen() + _breakEven)) : "") +
			(_isParcial ? "\nPARCIAL " + 
				(!_isPrimeiraParcial && _primeiraParcialInicio > 0 ? DoubleToString((GetPositionType() == POSITION_TYPE_SELL ? 
				                                                                     GetPositionPriceOpen() - _primeiraParcialInicio : 
				                                                                     GetPositionPriceOpen() + _primeiraParcialInicio), _Digits) + " " + (string)_primeiraParcialVolume + " " : "") +
				                                                                     
				(!_isSegundaParcial && _segundaParcialInicio > 0 ? " | " + DoubleToString((GetPositionType() == POSITION_TYPE_SELL ? 
				                                                                           GetPositionPriceOpen() - _segundaParcialInicio : 
				                                                                           GetPositionPriceOpen() + _segundaParcialInicio), _Digits) + " " + (string)_segundaParcialVolume + " " : "") +
				                                                                           
				(!_isTerceiraParcial && _terceiraParcialInicio > 0 ? " | " + DoubleToString((GetPositionType() == POSITION_TYPE_SELL ? 
				                                                                             GetPositionPriceOpen() - _terceiraParcialInicio : 
				                                                                             GetPositionPriceOpen() + _terceiraParcialInicio), _Digits) + " " + (string)_terceiraParcialVolume + " "  : "") 
			: "") +
			
			(_isGerenciamentoFinanceiro ? "\nPROFIT " + (string)GetTotalLucro() : "") +
			
			"\n--------------------------------------" +

			("\n" + _logger.Get()));

	}

	protected:	

   void SetInfo(string value)
	{
		if(_lastTextInfo != value)
		{
			_lastTextInfo = value;
			_isRewrite = true;
		}
	}

	int GetPositionType()
	{
		return (int)PositionGetInteger(POSITION_TYPE);
	}

	double GetPositionGain()
	{
		return PositionGetDouble(POSITION_TP);
	}

	double GetPositionLoss()
	{
		return PositionGetDouble(POSITION_SL);
	}

	int GetPositionMagicNumber()
	{
		return (int)PositionGetInteger(POSITION_MAGIC);
	}

	double GetPositionPriceOpen()
	{
		return NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN), _Digits);
	}

	double GetPositionVolume()
	{
		return PositionGetDouble(POSITION_VOLUME);
	}

	bool HasPositionLossOrPositionGain()
	{
		return GetPositionLoss() > 0.0 && GetPositionGain() > 0.0;
	}

	MqlTick GetPrice()
	{
		return _price;
	}

	MqlDateTime GetTimeCurrent()
	{
		TimeCurrent(_timeCurrent);
		return _timeCurrent;
	}

	bool Validate()
	{

		bool isValid = true;
		MqlDateTime time = GetTimeCurrent();

		if (time.hour < GetHoraInicio().hour || time.hour >= GetHoraFim().hour)
		{
			isValid = false;
		}

		if (time.hour == GetHoraInicio().hour && time.min < GetHoraInicio().min)
		{
			isValid = false;
		}

		if (time.hour == GetHoraFim().hour && time.min < GetHoraFim().min)
		{
			isValid = false;
		}

		if (!isValid)
		{
			_logger.Log("Horário não permitido! Somente entre " + _horaInicioString + " e " + _horaFimString);
		}

		if (isValid)
		{
			if (time.hour == GetHoraInicioIntervalo().hour)
			{
				if (time.min >= GetHoraInicioIntervalo().min)
				{
					isValid = false;
				}
			}

			if (time.hour == GetHoraFimIntervalo().hour)
			{
				if (time.min <= GetHoraFimIntervalo().min)
				{
					isValid = false;
				}
			}

			if (!isValid)
			{
				_logger.Log("Horário não permitido! Somente fora do intervalo de " + _horaInicioIntervaloString + " e " + _horaFimIntervaloString);
			}
		}

		if (!_isAlertMode && isValid)
		{

			if (_isGerenciamentoFinanceiro)
			{

				if (GetTotalLucro() >= _maximoLucroDiario)
				{
					isValid = false;
					_logger.Log("Lucro máximo atingido. R$ " + (string)GetTotalLucro());
				}

				if (GetTotalLucro() <= _maximoPrejuizoDiario)
				{
					isValid = false;
					_logger.Log("Prejuizo máximo atingido. R$ " + (string)GetTotalLucro());
				}
			}

			if (_isParcial && (_primeiraParcialVolume + _segundaParcialVolume + _terceiraParcialVolume) > _volume)
			{
				isValid = false;
				_logger.Log("Valores de parciais inválidos! Verifique-os.");
			}

			if (_isBreakEven)
			{
				if (_breakEven > _breakEvenInicio)
				{
					isValid = false;
					_logger.Log("O Valor do break-even não pode ser maior do que do valor de inicio do mesmo.");
				}
			}

			if (HasOrderOpen())
			{
				_logger.Log("Existem ordem(s) pendente(s) aguardando execução.");
				isValid = false;
			}

		}

		if (_isRewrite)
		{		
			Comment("--------------------------------------" +
				"\n" + GetRobotName() + " " + ToPeriodText(_period) + " " + GetRobotVersion() + "\nFRAMEWORK " + version +
				"\n--------------------------------------" +
				"\n" + _logger.Get() +
				"\n--------------------------------------");

			if (_logger.Last() != _lastTextValidate)
			{
				SendNotification(_logger.Last());
				SendMail(_robotName, _logger.Last());
			}

			_lastTextValidate = _logger.Last();

		}


		return isValid;


	}

	void ShowMessage(string text)
	{

		if (text != "" && text != _lastText)
		{
			string message = GetRobotName() + " (" + GetSymbol() + ", " + ToPeriodText(_period) + ")" + ": " + text;

			if (_isAlertMode)
			{
				Alert(message);
			}
			else
			{
				_logger.Log(text);
			}

			if (_isNotificacoesApp)
			{
				SendNotification(message);
			}
		}

		_lastText = text;

	}

	void Buy(double price)
	{

		if (!Validate())
		{
			return;
		}

		double stopGain = NormalizeDouble((price + GetStopGain()), _Digits);
		double stopLoss = NormalizeDouble((price - GetStopLoss()), _Digits);

		string msg = "Compra em " + (string)price + " GAIN: " + (string)stopGain + " LOSS: " + (string)stopLoss;

		_logger.Log(msg);

		if (_isAlertMode)
		{
			Alert(msg);
			return;
		}

		_trade.Buy(_volume, _symbol, price, stopLoss, stopGain, "ORDEM AUTOMATICA - " + _robotName);
		RestartManagePosition();
	}

	void Sell(double price)
	{

		if (!Validate())
		{
			return;
		}

		double stopGain = NormalizeDouble((price - GetStopGain()), _Digits);
		double stopLoss = NormalizeDouble((price + GetStopLoss()), _Digits);

		string msg = "Venda em: " + (string)price + " GAIN: " + (string)stopGain + " LOSS: " + (string)stopLoss;

		_logger.Log(msg);

		if (_isAlertMode)
		{
			Alert(msg);
			return;
		}

		_trade.Sell(_volume, _symbol, price, stopLoss, stopGain, "ORDEM AUTOMATICA - " + _robotName);
		RestartManagePosition();
	}

	void ClosePosition()
	{
		_trade.PositionClose(_symbol);
		_logger.Log("Posição total zerada.");
	}

	bool HasPositionOpen()
	{
		return _positionInfo.Select(_symbol) && GetPositionMagicNumber() == _trade.RequestMagic();
	}

	bool HasOrderOpen()
	{

		int orderCount = 0;

		for (int i = 0; i < OrdersTotal(); i++)
		{
			if (OrderSelect(OrderGetTicket(i)) && OrderGetString(ORDER_SYMBOL) == _symbol && OrderGetInteger(ORDER_MAGIC) == _trade.RequestMagic())
			{
				orderCount++;
			}
		}

		return orderCount > 0;

	}

	bool ExecuteBase()
	{

		if (!SymbolInfoTick(_symbol, _price))
		{
			Alert("Erro ao obter a última cotação de preço:", GetLastError());
			return false;
		}

		_isNewCandle = SetIsNewCandle();
		_isRewrite = _logger.HasChanges() || _isRewrite;

		if (HasPositionOpen())
		{

			ManagePosition();
			ShowInfo();

			return false;
		}

		ManageDealsProfit();
			
		if (!Validate())
		{
			return false;
		}

		_isNewDay = SetIsNewday();
		
		ShowInfo();
		
		_isRewrite = false;

		return true;

	}

	void ExecuteOnTradeBase()
	{

		ManageDealsProfit();

		if (_isParcial)
		{
			ManageDrawParcial();
		}
	}

	public:

	BadRobot()
	{
		_logger = new Logger();
		_account = new Account();
		_trade.LogLevel(LOG_LEVEL_ERRORS);
	}

	void SetPeriod(ENUM_TIMEFRAMES period)
	{
		_period = period;
	};

	ENUM_TIMEFRAMES GetPeriod()
	{
		return _period;
	};

	string ToPeriodText(ENUM_TIMEFRAMES period)
	{

		string aux[];

		StringSplit(EnumToString(period), '_', aux);

		return aux[1];

	};

	void SetSymbol(string symbol)
	{
		_symbol = symbol;
	};

	void SetVolume(double volume)
	{
		_volume = volume;
	}

	double GetVolume()
	{
		return _volume;
	};;

	string GetSymbol()
	{
		return _symbol;
	}

	void SetSpread(double value)
	{
		_spread = value;
	};

	void SetIsClosePosition(bool value)
	{
		_isClosePosition = value;
	}

	double GetSpread()
	{
		return _spread;
	}

	void SetStopGain(double value)
	{
		_stopGain = value;
	};

	double GetStopGain()
	{
		return _stopGain;
	};

	void SetStopLoss(double value)
	{
		_stopLoss = value;
	};

	double GetStopLoss()
	{
		return _stopLoss;
	};

	void SetIsStopOnLastCandle(bool value)
	{
		_isStopOnLastCandle = value;
	}

	void SetSpreadStopOnLastCandle(double value)
	{
		_spreadStopOnLastCandle = value;
	}
	
	void SetIsPeriodCustomStopOnLastCandle(bool value)
	{
		_isPeriodCustom = value;
	}
	
	void SetPeriodStopOnLastCandle(ENUM_TIMEFRAMES period)
	{
		_periodStopOnLastCandle = period;
	};
	
	void SetWaitBreakEvenExecuted(bool value)
	{
		_waitBreakEvenExecuted = value;
	}

	double GetSpreadStopOnLastCandle()
	{
		return _spreadStopOnLastCandle;
	}

	void SetNumberMagic(ulong value)
	{
		_trade.SetExpertMagicNumber(value);
	}

	double GetTotalLucro()
	{
		return _totalProfitMoney + _totalStopLossMoney;
	}

	MqlDateTime GetHoraInicio()
	{
		return _horaInicio;
	};

	MqlDateTime GetHoraFim()
	{
		return _horaFim;
	};

	MqlDateTime GetHoraInicioIntervalo()
	{
		return _horaInicioIntervalo;
	};

	MqlDateTime GetHoraFimIntervalo()
	{
		return _horaFimIntervalo;
	};

	void SetHoraInicio(string hora)
	{
		_horaInicioString = hora;
		TimeToStruct(StringToTime("1990.04.02 " + hora), _horaInicio);
	};

	void SetHoraFim(string hora)
	{
		_horaFimString = hora;
		TimeToStruct(StringToTime("1990.04.02 " + hora), _horaFim);
	};

	void SetHoraInicioIntervalo(string hora)
	{
		_horaInicioIntervaloString = hora;
		TimeToStruct(StringToTime("1990.04.02 " + hora), _horaInicioIntervalo);
	};

	void SetHoraFimIntervalo(string hora)
	{
		_horaFimIntervaloString = hora;
		TimeToStruct(StringToTime("1990.04.02 " + hora), _horaFimIntervalo);
	};

	void SetMaximoLucroDiario(double valor)
	{
		_maximoLucroDiario = valor;
	};

	void SetMaximoPrejuizoDiario(double valor)
	{
		_maximoPrejuizoDiario = valor * -1;
	};

	void SetIsTrailingStop(bool flag)
	{
		_isTrailingStop = flag;
	}

	void SetTrailingStopInicio(double valor)
	{
		_trailingStopInicio = valor;
	};

	void SetTrailingStop(double valor)
	{
		_trailingStop = valor;
	};

	void SetIsBreakEven(bool flag)
	{
		_isBreakEven = flag;
	}

	void SetBreakEven(double valor)
	{
		_breakEven = valor;
	}

	void SetBreakEvenInicio(double valor)
	{
		_breakEvenInicio = valor;
	};

	void SetIsParcial(bool flag)
	{
		_isParcial = flag;
	}

	void SetPrimeiraParcialInicio(double valor)
	{
		_primeiraParcialInicio = valor;
	}

	void SetPrimeiraParcialVolume(double valor)
	{
		_primeiraParcialVolume = valor;
	}

	void SetSegundaParcialInicio(double valor)
	{
		_segundaParcialInicio = valor;
	}

	void SetSegundaParcialVolume(double valor)
	{
		_segundaParcialVolume = valor;
	}

	void SetTerceiraParcialInicio(double valor)
	{
		_terceiraParcialInicio = valor;
	}

	void SetTerceiraParcialVolume(double valor)
	{
		_terceiraParcialVolume = valor;
	}

	void SetIsGerenciamentoFinanceiro(bool flag)
	{
		_isGerenciamentoFinanceiro = flag;
	}

	void SetRobotName(string name)
	{
		_robotName = name;
	}

	string GetRobotName()
	{
		return _robotName;
	}

	void SetRobotVersion(string valor)
	{
		_robotVersion = valor;
	}

	string GetRobotVersion()
	{
		return _robotVersion;
	}

	void SetIsNotificacoesApp(bool flag)
	{
		_isNotificacoesApp = flag;
	}

	void SetIsAlertMode(bool flag)
	{
		_isAlertMode = flag;
	}

	bool GetIsNewCandle()
	{
		return _isNewCandle;
	}

	bool GetIsNewDay()
	{
		return _isNewDay;
	}

};