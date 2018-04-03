classdef Mixture < dContinuous % dEither % Probably fastest to handle Mixtures of discrete RVs via ListRV mechanism.
    % Mixture(p1,BasisRV1,p2,BasisRV2,...,pk,BasisRVk) creates a random variable that is
    %  a mixture of the indicated basis RVs with the indicated probabilities.
    % The final pk is ignored can be omitted.
    
    properties(SetAccess = protected)
        NDists,          % Number of distributions that contribute to the mixture.
        BasisRV,         % Cell array with the individual distributions in the mixture.
        CumNParms,       % Cumulative count of parameters up to & including the i'th distrib (includes MixtureP's).
        DistParmCodes,   % Cell array with parmcodes for each distribution separately.
        % Note: The P arrays have NDist positions but the last one is always fixed, because its P is determined by the others.
        % Therefore, the last P is NOT counted as a parameter.
        MixtureP,        % Probability of each distribution within the mixture.
        CumulativeP,     % Cumulative probability of all distributions up to & including the i'th one.
        DistParmP,       % List of parmcodes for the individual MixtureP's.  Last one always 'f'
        PreviousParmCodes  % Holds the parmcodes passed last time; recompute DistParmP & DistParmCodes if this changes.
    end
    
    properties
        AdjustMixturePs % true/false: Controls whether probabilities are adjusted when fitting parameters
    end
    
    methods
        
        function obj=Mixture(varargin)
            obj=obj@dContinuous('Mixture');
            obj.AdjustMixturePs = false;
            switch nargin
                case 0
                case {1, 2}
                    ME = MException('Mixture:Constructor', ...
                        'Mixture constructor needs 0 or 3+ arguments.');
                    throw(ME);
                otherwise
                    Setup(obj,varargin(:));
                    ResetParms(obj,[obj.ParmValues]);
            end
        end
        
        function Setup(obj,s)
            npairs = numel(s);
            obj.Initialized = false;
            obj.NDists = floor((npairs+1)/2);
            obj.MixtureP = zeros(obj.NDists,1);
            obj.BasisRV = cell(obj.NDists,1);
            obj.CumulativeP = zeros(obj.NDists,1);
            obj.CumNParms =zeros(obj.NDists,1);
            obj.DistParmP = char(obj.NDists);
            obj.DistParmCodes = cell(obj.NDists,1);
            obj.PreviousParmCodes = '9';   % Reset to an impossible value so that new ones will be computed by CheckNewParmCodes.
            nextptr = 0;
            for iDist=1:obj.NDists
                nextptr = nextptr + 1;
                %                 disp(s{nextptr});
                if nextptr < npairs
                    obj.MixtureP(iDist) = s{nextptr};
                    nextptr = nextptr + 1;
                else
                    obj.MixtureP(iDist) = 1 - sum(obj.MixtureP(1:iDist-1));  % Not saved
                end
                obj.BasisRV{iDist} = s{nextptr};
                assert(obj.BasisRV{iDist}.Initialized,['Unable to initialize Mixture BasisRV number ' num2str(iDist)]);
            end
            
            % Determine distribution type:
            OneIsDiscrete = false;
            OneIsContinuous = false;
            OneIsMixed = false;
            for I = 1:obj.NDists
                if obj.BasisRV{I}.DistType == 'c'; OneIsContinuous = true; end
                if obj.BasisRV{I}.DistType == 'd'; OneIsDiscrete = true; end
                if obj.BasisRV{I}.DistType == 'm'; OneIsMixed = true; end
            end
            if OneIsContinuous && ~(OneIsDiscrete || OneIsMixed)
                obj.DistType = 'c';
            else
                assert(false,'Mixture can only handle continuous Basis distributions (so far)');
            end
            
            % Assemble DefaultParmCodes & count NDistParms & CumNParms
            if obj.AdjustMixturePs
                ParmCodeForP = 'r';
            else
                ParmCodeForP = 'f';
            end
            obj.NDistParms = 0;
            obj.DefaultParmCodes = '';
            for iDist=1:obj.NDists
                if iDist == obj.NDists
                    ParmCodeForP = 'f';
                end
                if ParmCodeForP == 'r'
                    obj.NDistParms = obj.NDistParms + 1;
                end
                obj.DistParmP(iDist) = ParmCodeForP;
                if iDist < obj.NDists
                    obj.DefaultParmCodes = [obj.DefaultParmCodes ParmCodeForP];
                end
                obj.DefaultParmCodes = [obj.DefaultParmCodes obj.BasisRV{iDist}.DefaultParmCodes];
                obj.NDistParms = obj.NDistParms + obj.BasisRV{iDist}.NDistParms;
                obj.CumNParms(iDist) = obj.NDistParms;
            end
            obj.NDistParms = obj.NDistParms + obj.NDists - 1;  % Count the free P's
            %             fprintf('NDistParms is %f and parmcodes is %s\n',obj.NDistParms,obj.DefaultParmCodes);
        end
        
        function BuildMyName(obj)
            sTemp = [num2str(obj.MixtureP(1)) ',' obj.BasisRV{1}.StringName];
            for iDist=2:obj.NDists
                sTemp = [sTemp ',' num2str(obj.MixtureP(iDist)) ',' obj.BasisRV{iDist}.StringName];
            end
            obj.StringName = ['Mixture(' sTemp ')'];
        end
        
        function []=ResetParms(obj,newparmvalues)
            CheckBeforeResetParms(obj,newparmvalues)
            obj.Initialized = true;
            ParmsUsed = 0;
            for iDist = 1:obj.NDists
                if iDist<obj.NDists
                    ParmsUsed = ParmsUsed + 1;
                    obj.MixtureP(iDist) = newparmvalues(ParmsUsed);
                else
                    obj.MixtureP(iDist) = 1 - sum(obj.MixtureP(1:iDist-1));
                end
                obj.BasisRV{iDist}.ResetParms(newparmvalues(ParmsUsed+1:ParmsUsed+obj.BasisRV{iDist}.NDistParms));
                ParmsUsed = ParmsUsed + obj.BasisRV{iDist}.NDistParms;
            end
            ReInit(obj);
        end
        
        function PerturbParms(obj,ParmCodes)
            ParmsUsed = 0;
            for iDist = 1:obj.NDists
                if iDist<obj.NDists
                    ParmsUsed = ParmsUsed + 1;
                    obj.MixtureP(iDist) = ifelse(ParmCodes(ParmsUsed)=='f',obj.MixtureP(iDist),0.95*obj.MixtureP(iDist));
                end
                obj.BasisRV{iDist}.PerturbParms(ParmCodes(ParmsUsed+1:ParmsUsed+obj.BasisRV{iDist}.NDistParms));
                ParmsUsed = ParmsUsed + obj.BasisRV{iDist}.NDistParms;
            end
            obj.ReInit;
        end
        
        function ReInit(obj)
            % Assume all distributions have been initialized
            
            % Check for legal mixture probabilities & compute cumulative mixture probabilities across distributions
            MixPSum = 0;
            for iDist = 1:obj.NDists-1
                assert(obj.MixtureP(iDist)>=0,'Mixture probabilities must be >= 0.');
                MixPSum = MixPSum + obj.MixtureP(iDist);
                obj.CumulativeP(iDist) = MixPSum;
            end
            assert(MixPSum<=1,'Sum of first n-1 mixture probabilities cannot exceed 1.');
            obj.MixtureP(obj.NDists) = 1 - MixPSum;
            obj.CumulativeP(obj.NDists) = 1;
            
            obj.LowerBound = inf;
            obj.UpperBound = -inf;
            for iDist=1:obj.NDists
                if obj.MixtureP(iDist) > 0
                    if obj.LowerBound > obj.BasisRV{iDist}.LowerBound
                        obj.LowerBound = obj.BasisRV{iDist}.LowerBound;
                    end
                    if obj.UpperBound < obj.BasisRV{iDist}.UpperBound
                        obj.UpperBound = obj.BasisRV{iDist}.UpperBound;
                    end
                end
            end
            obj.Initialized = true;
            if (obj.NameBuilding)
                BuildMyName(obj);
            end
        end
        
        function thispdf=PDF(obj,X)
            [thispdf, InBounds, Done] = MaybeSplinePDF(obj,X);
            if Done
                return;
            end
            for iDist=1:obj.NDists
                thispdf = thispdf + obj.BasisRV{iDist}.PDF(X)*obj.MixtureP(iDist);
            end
        end
        
        function thiscdf=CDF(obj,X)
            [thiscdf, InBounds, Done] = MaybeSplineCDF(obj,X);
            if Done
                return;
            end
            for iDist=1:obj.NDists
                thiscdf(InBounds) = thiscdf(InBounds) + obj.BasisRV{iDist}.CDF(X(InBounds))*obj.MixtureP(iDist);
            end
        end
        
        function Reals = ParmsToReals(obj,Parms,~)
            Reals = [];
            ParmsUsed = 0;
            RunningTotalP = 0;
            for iDist=1:obj.NDists
                if iDist<obj.NDists
                    ParmsUsed = ParmsUsed + 1;
                    Reals = [Reals NumTrans.Bounded2Real(0,1-RunningTotalP,obj.MixtureP(iDist))];
                    RunningTotalP = RunningTotalP + obj.MixtureP(iDist);
                end
                Reals = [Reals obj.BasisRV{iDist}.ParmsToReals(Parms(ParmsUsed+1:ParmsUsed+obj.BasisRV{iDist}.NDistParms))];
                ParmsUsed = ParmsUsed + obj.BasisRV{iDist}.NDistParms;
            end
        end
        
        function Parms = RealsToParms(obj,Reals,~)
            Parms = [];
            ParmsUsed = 0;
            RunningTotalP = 0;
            for iDist=1:obj.NDists
                if iDist<obj.NDists
                    ParmsUsed = ParmsUsed + 1;
                    Parms = [Parms NumTrans.Real2Bounded(0,1-RunningTotalP,Reals(ParmsUsed))];
                    RunningTotalP = RunningTotalP + obj.MixtureP(iDist);
                end
                Parms = [Parms obj.BasisRV{iDist}.RealsToParms(Reals(ParmsUsed+1:ParmsUsed+obj.BasisRV{iDist}.NDistParms))];
                ParmsUsed = ParmsUsed + obj.BasisRV{iDist}.NDistParms;
            end
        end
        
        function parmvals = ParmValues(obj)
            parmvals = [];
            for iDist=1:obj.NDists
                if iDist<obj.NDists
                    parmvals = [parmvals obj.MixtureP(iDist)];
                end
                parmvals = [parmvals obj.BasisRV{iDist}.ParmValues];
            end
        end
        
        function thisval=Mean(obj)
            assert(obj.Initialized,UninitializedError(obj));
            thisval = 0;
            for iDist=1:obj.NDists
                thisval = thisval + obj.BasisRV{iDist}.Mean*obj.MixtureP(iDist);
            end
        end
        
        function thisval=Variance(obj)
            assert(obj.Initialized,UninitializedError(obj));
            EX = 0;
            EXX = 0;
            for iDist=1:obj.NDists
                thismu = obj.BasisRV{iDist}.Mean;
                thisvar = obj.BasisRV{iDist}.Variance;
                EX = EX + thismu*obj.MixtureP(iDist);
                EXX = EXX + (thisvar + thismu^2)*obj.MixtureP(iDist);
            end
            thisval = EXX - EX^2;
        end
        
        function thisval=RawMoment(obj,N)
            if obj.DistType == 'c'
                thisval = 0;
                for iDist = 1:obj.NDists
                    This = obj.BasisRV{iDist}.RawMoment(N);
                    thisval = This * obj.MixtureP(iDist) + thisval;
                end
            else
                assert(false,'Unable to compute Mixture distribution RawMoment.');
            end
        end
        
        function thisval=IntegralXToNxPDF(obj,FromX,ToX,N)
            if obj.DistType == 'c'
                thisval = 0;
                for iDist = 1:obj.NDists
                    This = obj.BasisRV{iDist}.IntegralXToNxPDF(FromX,ToX,N);
                    thisval = This * obj.MixtureP(iDist) + thisval;
                end
            else
                assert(false,'Unable to compute Mixture distribution IntegralXToNxPDF.');
            end
        end
        
        function thisval=Random(obj,varargin)
            assert(obj.Initialized,UninitializedError(obj));
            thisval = zeros(varargin{:});
            for iel=1:numel(thisval)
                thisp = rand;
                iDist = find(thisp<=obj.CumulativeP,1);  % find the first distribution with thisp<=CumProb
                thisval(iel) = obj.BasisRV{iDist}.Random;
            end
        end
        
    end  % methods
    
end  % class Mixture



