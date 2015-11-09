classdef GLM
    properties (Access=public)
        expRef;
        modelString;
        parameterLabels;
        parameterFits;
        parameterBounds;
        parameterStart;
        ZL;
        ZR;
        data;
        p_hat;
    end
    
    properties (Access=private)
        ContrastDimensions;
    end
    
    methods
        function obj = GLM(inputData)
            if isa(inputData,'struct')
                %If input is a struct containing AT MINIMUM the fields:
                %                 -contrast_cond
                %                 -response
                %                 -repeatNum
                obj.data = inputData;
                obj.expRef = 'none';
                
            elseif isa(inputData,'char')
                %if expRef, then load using the dat package
                obj.expRef = inputData;
                block = dat.loadBlock(obj.expRef);
                trials = block.trial;
                D = struct;
                
                for t=1:block.numCompletedTrials
                    D.contrast_cond(t,:) = trials(t).condition.visCueContrast';
                    D.response(t,1) = trials(t).responseMadeID';
                    D.repeatNum(t,1) = trials(t).condition.repeatNum;
                end
                
                obj.data = D;
            else
                error('GLM:constructorFail', 'Must pass either an expRef or data struct to GLM constructor');
            end
            
            if any(min(obj.data.contrast_cond,[],2)>0)
                obj.ContrastDimensions = 2;
            else
                obj.ContrastDimensions = 1;
            end
            
        end
        
        function obj = setModel(obj,modelString)
            obj.modelString = modelString;
            obj.parameterFits = [];
            obj.parameterStart = [];
            
            switch(modelString)
                case 'Offset' %Model guesses based on the proportion of responses in the data
                    %used as a baseline to compare other models
                    obj.parameterLabels = {'Offset_L','Offset_R'};
                    obj.parameterBounds = [-inf -inf; +inf +inf];
                    obj.ZL = @(P,CL,CR)(P(1)*ones(length(CL),1));
                    obj.ZR = @(P,CL,CR)(P(2)*ones(length(CR),1));
                case 'fullContrasts'
                    uniqueC = unique(obj.data.contrast_cond,'rows');
                    obj.parameterLabels = models.fullContrast('paramLabels',[],[],[],uniqueC);
                    obj.parameterBounds = models.fullContrast('paramBounds',[],[],[],uniqueC);
                    obj.ZL = @(P,CL,CR)(models.fullContrast('L',P,CL,CR,uniqueC));
                    obj.ZR = @(P,CL,CR)(models.fullContrast('R',P,CL,CR,uniqueC));
                case 'fullContrasts-subset'
                    uniqueC = unique(obj.data.contrast_cond,'rows');
                    obj.parameterLabels = models.fullContrast_subset('paramLabels',[],[],[],uniqueC);
                    obj.parameterBounds = models.fullContrast_subset('paramBounds',[],[],[],uniqueC);
                    obj.ZL = @(P,CL,CR)(models.fullContrast_subset('L',P,CL,CR,uniqueC));
                    obj.ZR = @(P,CL,CR)(models.fullContrast_subset('R',P,CL,CR,uniqueC));
                case 'CL+CR'
                    obj.parameterLabels = {'Offset_L','ScaleL_L','ScaleR_L','Offset_R','ScaleL_R','ScaleR_R'};
                    obj.parameterBounds = [-inf -inf -inf -inf -inf -inf;
                        +inf +inf +inf +inf +inf +inf];
                    obj.ZL = @(P,CL,CR)(P(1) + P(2).*CL + P(3).*CR);
                    obj.ZR = @(P,CL,CR)(P(4) + P(5).*CL + P(6).*CR);
                case 'CL+CR-subset'
                    obj.parameterLabels = {'Offset_L','ScaleL_L','Offset_R','ScaleR_R'};
                    obj.parameterBounds = [-inf -inf -inf -inf;
                        +inf +inf +inf +inf];
                    obj.ZL = @(P,CL,CR)(P(1) + P(2).*CL);
                    obj.ZR = @(P,CL,CR)(P(3) + P(4).*CR);
                case 'C^N'
                    obj.parameterLabels = {'Offset_L','ScaleL_L','ScaleR_L','Offset_R','ScaleL_R','ScaleR_R','N'};
                    obj.parameterBounds = [-inf -inf -inf -inf -inf -inf 0;
                        +inf +inf +inf +inf +inf +inf +inf];
                    obj.ZL = @(P,CL,CR)(P(1) + P(2).*CL.^P(7) + P(3).*CR.^P(7));
                    obj.ZR = @(P,CL,CR)(P(4) + P(5).*CL.^P(7) + P(6).*CR.^P(7));
                case 'C^N-subset'
                    obj.parameterLabels = {'Offset_L','ScaleL_L','Offset_R','ScaleR_R','N'};
                    obj.parameterBounds = [-inf -inf -inf -inf 0;
                        +inf +inf +inf +inf +inf];
                    obj.ZL = @(P,CL,CR)(P(1) + P(2).*CL.^P(5));
                    obj.ZR = @(P,CL,CR)(P(3) + P(4).*CR.^P(5));
                case 'C^NL^NR'
                    obj.parameterLabels = {'Offset_L','ScaleL_L','ScaleR_L','Offset_R','ScaleL_R','ScaleR_R','NL','NR'};
                    obj.parameterBounds = [-inf -inf -inf -inf -inf -inf 0 0;
                        +inf +inf +inf +inf +inf +inf +inf +inf];
                    obj.ZL = @(P,CL,CR)(P(1) + P(2).*CL.^P(7) + P(3).*CR.^P(8));
                    obj.ZR = @(P,CL,CR)(P(4) + P(5).*CL.^P(7) + P(6).*CR.^P(8));
                case 'C^NL^NR-subset'
                    obj.parameterLabels = {'Offset_L','ScaleL_L','Offset_R','ScaleR_R','NL','NR'};
                    obj.parameterBounds = [-inf -inf -inf -inf 0 0;
                        +inf +inf +inf +inf +inf +inf];
                    obj.ZL = @(P,CL,CR)(P(1) + P(2).*CL.^P(5));
                    obj.ZR = @(P,CL,CR)(P(3) + P(4).*CR.^P(6));
                case 'C50'
                    obj.parameterLabels = {'Offset_L','ScaleL_L','ScaleR_L','Offset_R','ScaleL_R','ScaleR_R','N','C50'};
                    obj.parameterBounds = [-inf -inf -inf -inf -inf -inf 0 0;
                        +inf +inf +inf +inf +inf +inf +inf +inf];
                    obj.ZL = @(P,CL,CR)(P(1) + P(2).*(CL.^P(7))./(CL.^P(7) + P(8)) + P(3).*(CR.^P(7))./(CR.^P(7) + P(8)^P(7)));
                    obj.ZR = @(P,CL,CR)(P(4) + P(5).*(CL.^P(7))./(CL.^P(7) + P(8)) + P(6).*(CR.^P(7))./(CR.^P(7) + P(8)^P(7)));
                case 'C50-subset'
                    obj.parameterLabels = {'Offset_L','ScaleL_L','Offset_R','ScaleR_R','N','C50'};
                    obj.parameterBounds = [-inf -inf -inf -inf 0 0;
                        +inf +inf +inf +inf +inf +inf];
                    obj.ZL = @(P,CL,CR)(P(1) + P(2).*(CL.^P(5))./(CL.^P(5) + P(6)^P(5)));
                    obj.ZR = @(P,CL,CR)(P(3) + P(4).*(CR.^P(5))./(CR.^P(5) + P(6)^P(5)));
                case 'C50-subset(N=1)'
                    obj.parameterLabels = {'Offset_L','ScaleL_L','Offset_R','ScaleR_R','C50'};
                    obj.parameterBounds = [-inf -inf -inf -inf 0;
                        +inf +inf +inf +inf +inf];
                    N = 1;
                    obj.ZL = @(P,CL,CR)(P(1) + P(2).*(CL.^N)./(CL.^N + P(5)^N));
                    obj.ZR = @(P,CL,CR)(P(3) + P(4).*(CR.^N)./(CR.^N + P(5)^N));
                case 'Supersaturation-subset'
                    obj.parameterLabels = {'Offset_L','ScaleL_L','Offset_R','ScaleR_R','N','C50','S'};
                    obj.parameterBounds = [-inf -inf -inf -inf 0 0 0;
                        +inf +inf +inf +inf +inf +inf 10];
                    obj.ZL = @(P,CL,CR)(P(1) + P(2).*(CL.^P(5))./(CL.^(P(5)*P(7)) + P(6).^(P(5)*P(7))));
                    obj.ZR = @(P,CL,CR)(P(3) + P(4).*(CR.^P(5))./(CR.^(P(5)*P(7)) + P(6).^(P(5)*P(7))));
                case 'ifC'
                    obj.parameterLabels = {'Offset_L','ScaleL_L','Offset_R','ScaleR_R'};
                    obj.parameterBounds = [-inf -inf -inf -inf;
                        +inf +inf +inf +inf];
                    obj.ZL = @(P,CL,CR)(P(1) + P(2)*(CL>0));
                    obj.ZR = @(P,CL,CR)(P(3) + P(4)*(CR>0));
                case 'AFC'
                    obj.parameterLabels = {'Offset','ScaleL','ScaleR'};
                    obj.parameterBounds = [-inf -inf -inf; +inf +inf +inf];
                    obj.ZL = @(P,CL,CR)(P(1) + P(2)*CL + P(3)*CR);
                    obj.ZR = [];
                otherwise
                    error('Model does not exist');
                    
            end
            
            if isempty(obj.parameterStart)
                obj.parameterStart = zeros(1,length(obj.parameterLabels));
            end
        end
        
        function obj = fit(obj)
            %Non crossvalidated fitting
            
            if isempty(obj.ZL)
                error('Please set a model first using method setModel(...)');
            end
            
            %Remove trials with repeats
            obj.data = obj.getrow(obj.data,obj.data.repeatNum==1);
            options = optimoptions('fmincon','UseParallel',0,'MaxFunEvals',10000,'MaxIter',2000);
            
            contrasts = obj.data.contrast_cond;
            responses = obj.data.response;
            [obj.parameterFits,~,exitflag] = fmincon(@(b) obj.calculateLogLik(b, contrasts, responses), obj.parameterStart(), [], [], [], [], obj.parameterBounds(1,:), obj.parameterBounds(2,:), [], options);
            if ~any(exitflag == [1,2])
                obj.parameterFits = nan(1,length(obj.parameterLabels));
            end
            
        end
        
        function obj = fitCV(obj)
            %Crossvalidated fitting
            
            if isempty(obj.ZL)
                error('Please set a model first using method setModel(...)');
            end
            
            %Remove trials with repeats
            obj.data = obj.getrow(obj.data,obj.data.repeatNum==1);
            options = optimoptions('fmincon','UseParallel',0,'MaxFunEvals',10000,'MaxIter',2000);
            
            C = cvpartition(length(obj.data.response),'LeaveOut');
            obj.parameterFits = nan(C.NumTestSets,length(obj.parameterLabels));
            for f=1:C.NumTestSets
                disp(['Model: ' obj.modelString '. Fold: ' num2str(f) '/' num2str(C.NumTestSets)]);
                trainIdx = find(C.training(f)==1);
                testIdx = find(C.test(f)==1);
                
                trainContrasts = obj.data.contrast_cond(trainIdx,:);
                trainResponses = obj.data.response(trainIdx);
                testContrast = obj.data.contrast_cond(testIdx,:);
                testResponse = obj.data.response(testIdx);
                
                [obj.parameterFits(f,:),~,exitflag] = fmincon(@(b) obj.calculateLogLik(b, trainContrasts, trainResponses), obj.parameterStart(), [], [], [], [], obj.parameterBounds(1,:), obj.parameterBounds(2,:), [], options);
                
                if ~any(exitflag == [1,2])
                    obj.parameterFits(f,:) = nan(1,length(obj.parameterLabels));
                end
                
                phat = obj.calculatePhat(obj.parameterFits(f,:), testContrast);
                
                obj.p_hat(testIdx,1) = phat(testResponse);
            end
        end
        
        function h = plotData(obj)
            switch(obj.ContrastDimensions)
                case 1
                    contrast1D = obj.data.contrast_cond(:,2) - obj.data.contrast_cond(:,1);
                    uniqueC1D = unique(contrast1D);
                    prop=[];
                    for c = 1:length(uniqueC1D)
                        D = obj.getrow(obj.data,contrast1D == uniqueC1D(c));
                        p = sum([D.response==1 D.response==2 D.response==3])/length(D.response);
                        prop = [prop;p];
                    end
                    
                    plot(uniqueC1D,prop,'.','MarkerSize',20);
                    xlabel('Contrast1D');
                    ylabel('% choice');
                    
                    h=gca;
                    
                case 2
                    uniqueCL = unique(obj.data.contrast_cond(:,1));
                    uniqueCR = unique(obj.data.contrast_cond(:,2));
                    prop=nan(length(uniqueCL),length(uniqueCR),3);
                    
                    for cl = 1:length(uniqueCL)
                        for cr = 1:length(uniqueCR)
                            E = obj.getrow(obj.data,obj.data.contrast_cond(:,1) == uniqueCL(cl) & obj.data.contrast_cond(:,2) == uniqueCR(cr));
                            for i=1:3
                                prop(cl,cr,i) = sum(E.response==i)/length(E.response);
                            end
                        end
                    end
                    
                    titles = {'%L','%R','%NG'};
                    for i=1:3
                        h(i)=subplot(2,3,i);
                        imagesc(uniqueCR,uniqueCL,prop(:,:,i),[0 1]);
                        set(gca,'YDir','normal');
                        
                        xlabel('C Right');
                        ylabel('C Left');
                        title(titles{i});
                        axis square;
                    end
            end
        end
        
        function fig = plotFit(obj)
            if size(obj.parameterFits,1)==1
                h=obj.plotData();
                
                switch (obj.ContrastDimensions)
                    case 1
                        hold on;
                        
                        if ~(strcmp(obj.modelString,'fullContrasts') || strcmp(obj.modelString,'fullContrasts-subset'))
                            maxC = max(max(obj.data.contrast_cond));
                            evalC = [linspace(maxC,0,100)', zeros(100,1);
                                zeros(100,1), linspace(0,maxC,100)'];
                            evalC1d = evalC(:,2) - evalC(:,1);
                            phat = obj.calculatePhat(obj.parameterFits,evalC);
                            set(gca, 'ColorOrderIndex', 1);
                            plot(h, evalC1d,phat);
                            title(obj.modelString);
                            hold off;
                            h=gca;
                        else
                            evalC = unique(obj.data.contrast_cond,'rows');
                            evalC1d = evalC(:,2) - evalC(:,1);
                            [~,sortIdx]=sort(evalC1d);
                            phat = obj.calculatePhat(obj.parameterFits,evalC);
                            set(gca, 'ColorOrderIndex', 1);
                            plot(h, evalC1d(sortIdx),phat(sortIdx,:),':');
                        end
                        title(obj.modelString);
                        hold off;
                        h=gca;
                        
                    case 2
                        h=obj.plotData;
                        fig=get(h(1),'Parent');
                        
                        evalCL = linspace(0,max(obj.data.contrast_cond(:,1)),100);
                        evalCR = linspace(0,max(obj.data.contrast_cond(:,1)),100);
                        prop=nan(length(evalCL),length(evalCR),3);
                        
                        for cl = 1:length(evalCL)
                            for cr = 1:length(evalCR)
                                p = obj.calculatePhat(obj.parameterFits,[evalCL(cl) evalCR(cr)]);
                                for i=1:3
                                    prop(cl,cr,i) = p(i);
                                end
                            end
                        end
                        
                        figure(fig);
                        titles = {'Pred %L','Pred %R','Pred %NG'};
                        for i=1:3
                            subplot(2,3,i+3);
                            imagesc(evalCR,evalCL,prop(:,:,i),[0 1]);
                            set(gca,'YDir','normal');
                            xlabel('C Right');
                            ylabel('C Left');
                            title(titles{i});
                            axis square;
                        end
                        
                end
            else
                error('Model not fitted (non-crossvalidated) yet');
            end
        end
        
        function h = plotParams(obj)
            if size(obj.parameterFits,1)==1
                bar(obj.parameterFits);
                set(gca,'XTickLabel',obj.parameterLabels,'XTick',1:numel(obj.parameterLabels));
                title(obj.modelString);
                h=gca;
            end
        end
        
        function phat = calculatePhat(obj,testParams,contrast_cond)
            if isempty(obj.ZL)
                error('Please set a model first using method setModel(...)');
            end
            
            cl = contrast_cond(:,1);
            cr = contrast_cond(:,2);
            
            if isempty(obj.ZR) %if a AFC task then no ZR is defined, only pL vs pR
                zl = obj.ZL(testParams,cl,cr);
                pL = exp(zl)./(1+exp(zl));
                pR = 1 - pL;
                N = length(pL);
                phat = [pL pR zeros(N,1)];
            else %if ADC task then ZL and ZR are defined to produce pL vs pNG and pR vs pNG
                zl = obj.ZL(testParams,cl,cr);
                zr = obj.ZR(testParams,cl,cr);
                pL = exp(zl)./(1+exp(zl)+exp(zr));
                pR = exp(zr)./(1+exp(zl)+exp(zr));
                pNG = 1 - pL - pR;
                
                phat = [pL pR pNG];
            end
        end
    end
    
    methods (Access= {?GLM})        
        function logLik = calculateLogLik(obj,testParams, contrast_conds, responses)
            phat = obj.calculatePhat(testParams, contrast_conds);
            logLik = -sum(log( phat(sub2ind(size(phat), [1:length(responses)]', responses)) ));
        end
        
        function row = getrow(~,D,numrow)
            % Version 1.0 9/18/03
            % by Joern Diedrichsen
            % http://www.icn.ucl.ac.uk/motorcontrol/toolboxes/toolbox_util.htm
            
            if (~isstruct(D))
                error('D must be a struct');
            end;
            
            field = fieldnames(D);
            row=[];
            for f=1:length(field)
                F = getfield(D,field{f});
                if iscell(F)
                    row = setfield(row,field{f},F(numrow,:));
                else
                    row = setfield(row,field{f},F(numrow,:));
                end
            end
            
        end
    end
end