classdef laserGLM < GLM
    % Subclass which handles experimental sessions involving optogenetic
    % inactivation. This is required since those sessions have different
    % sessions depending on the location and intensity of the laser
    % inactivation. Therefore trials must be split up accordingly.
    
    properties
        inactivationSite;
        
    end
    
    properties (Access=private)
        ZINPUT;
    end
    
    methods
        function obj = laserGLM(inputData)
            obj@GLM(inputData);
            
            if isa(inputData,'char')
                L=load(dat.expFilePath(inputData, 'laserManip', 'm'));
                obj.data.laser = L.laserCoordByTrial;
            end
            sites = unique(obj.data.laser(~isnan(obj.data.laser(:,1)),:),'rows');
            
            obj.inactivationSite = sites;
            obj.data.laserIdx = zeros(size(obj.data.laser,1),1);
            for i = 1:size(sites,1)
                idx=bsxfun(@(a,b)(a==b),sites(i,:),obj.data.laser);
                idx = sum(idx,2)==2;
                obj.data.laserIdx = obj.data.laserIdx + idx*i; 
            end
        end
        
        function obj = setModel(obj,modelString)
            obj.modelString = modelString;
            obj.parameterFits = [];
            obj.parameterStart = [];
            
            switch(modelString)
                case 'C^N-subset-nolaser'
                    obj.parameterLabels = {'Offset_L','ScaleL_L','Offset_R','ScaleR_R','N'};
                    obj.parameterBounds = [-inf(1,4) 0;
                        +inf(1,4) inf];
                    %Laser indicator variable included in ZL function
                    obj.ZINPUT = @(data)([data.contrast_cond(:,1) data.contrast_cond(:,2)]);
                    obj.ZL = @(P,INPUT)( P(1) + P(2).*INPUT(:,1).^P(5) );
                    obj.ZR = @(P,INPUT)( P(3) + P(4).*INPUT(:,2).^P(5) );
                case 'C^N-subset-laser'
                    obj.parameterLabels = {'Offset_L','ScaleL_L','Offset_R','ScaleR_R','laser-Offset_L','laser-ScaleL_L','laser-Offset_R','laser-ScaleR_R','N'};
                    obj.parameterBounds = [-inf(1,8) 0;
                        +inf(1,8) inf];
                    %Laser indicator variable included in ZL function
                    obj.ZINPUT = @(data)([data.contrast_cond(:,1) data.contrast_cond(:,2) ~isnan(data.laser(:,1))]);
                    obj.ZL = @(P,INPUT)( (1-INPUT(:,3)).*(P(1) + P(2).*INPUT(:,1).^P(9)) + INPUT(:,3).*(P(5) + P(6).*INPUT(:,1).^P(9)) );
                    obj.ZR = @(P,INPUT)( (1-INPUT(:,3)).*(P(3) + P(4).*INPUT(:,2).^P(9)) + INPUT(:,3).*(P(7) + P(8).*INPUT(:,2).^P(9)) );
                case 'C^N-subset-laser_Offset'
                    obj.parameterLabels = {'Offset_L','ScaleL_L','Offset_R','ScaleR_R','laser-Offset_L','laser-Offset_R','N'};
                    obj.parameterBounds = [-inf(1,6) 0;
                        +inf(1,6) inf];
                    obj.ZINPUT = @(data)([data.contrast_cond(:,1) data.contrast_cond(:,2) ~isnan(data.laser(:,1))]);
                    obj.ZL = @(P,INPUT)( (1-INPUT(:,3)).*P(1) + INPUT(:,3).*P(5) + P(2).*INPUT(:,1).^P(7) );
                    obj.ZR = @(P,INPUT)( (1-INPUT(:,3)).*P(3) + INPUT(:,3).*P(6) + P(4).*INPUT(:,2).^P(7) );
                case 'C^N-subset-laser_Scale'
                    obj.parameterLabels = {'Offset_L','ScaleL_L','Offset_R','ScaleR_R','laser-ScaleL_L','laser-ScaleR_R','N'};
                    obj.parameterBounds = [-inf(1,6) 0;
                        +inf(1,6) inf];
                    obj.ZINPUT = @(data)([data.contrast_cond(:,1) data.contrast_cond(:,2) ~isnan(data.laser(:,1))]);
                    obj.ZL = @(P,INPUT)( P(1) + (1-INPUT(:,3)).*(P(2).*INPUT(:,1).^P(7)) + INPUT(:,3).*(P(5).*INPUT(:,1).^P(7)) );
                    obj.ZR = @(P,INPUT)( P(3) + (1-INPUT(:,3)).*(P(4).*INPUT(:,2).^P(7)) + INPUT(:,3).*(P(6).*INPUT(:,2).^P(7)) );
              
                    
                otherwise
                    error('Model does not exist');
            end
            
            if isempty(obj.parameterStart)
                obj.parameterStart = zeros(1,length(obj.parameterLabels));
            end
        end
        
        function obj = getSubsetData(obj,siteID)
            %gets subset of data corresponding to a particular inactivation
            %site within a session. This is important as some sessions
            %contain trials with different inactivation sites.
            
            if ~isempty(siteID)
                obj.data = obj.getrow(obj.data,obj.data.laserIdx==siteID{1} | obj.data.laserIdx==0);
                if siteID{1} == 0
                    obj.inactivationSite = [NaN, NaN];
                else
                    obj.inactivationSite = obj.inactivationSite(siteID{1},:);
                end
                
                if ~any(siteID{1} == obj.data.laserIdx)
                    error('Inactivation site ID does not exist in this dataset');
                end
            end
            
        end
        
        function obj = fit(obj,varargin)
            obj = obj.getSubsetData(varargin);
            
            if size(obj.inactivationSite,1) > 1
                error('More than one inactivation site: please provide only subset corresponding to a single inactivation site');
            end
            
            %Remove trials with repeats
            obj.data = obj.getrow(obj.data,obj.data.repeatNum==1);
            
            options = optimoptions('fmincon','UseParallel',0,'MaxFunEvals',10000,'MaxIter',2000,'Display','off');
            
            inputs = obj.ZINPUT(obj.data);
            responses = obj.data.response;
            
            [obj.parameterFits,~,exitflag] = fmincon(@(b) obj.calculateLogLik(b, inputs, responses), obj.parameterStart(), [], [], [], [], obj.parameterBounds(1,:), obj.parameterBounds(2,:), [], options);
            if ~any(exitflag == [1,2])
                obj.parameterFits = nan(1,length(obj.parameterLabels));
            end
            
        end
        
        function obj = fitCV(obj,varargin)
            obj = obj.getSubsetData(varargin);
            
            if isempty(obj.ZL)
                error('Please set a model first using method setModel(...)');
            end
            
            %Remove trials with repeats
            obj.data = obj.getrow(obj.data,obj.data.repeatNum==1);
            options = optimoptions('fmincon','UseParallel',0,'MaxFunEvals',10000,'MaxIter',2000,'Display','off');
            
            C = cvpartition(length(obj.data.response),'LeaveOut');
            obj.parameterFits = nan(C.NumTestSets,length(obj.parameterLabels));
            for f=1:C.NumTestSets
                disp(['Model: ' obj.modelString '. Fold: ' num2str(f) '/' num2str(C.NumTestSets)]);
                trainIdx = find(C.training(f)==1);
                testIdx = find(C.test(f)==1);
                
                z_inputs = obj.ZINPUT(obj.data);
                trainInputs = z_inputs(trainIdx,:);
                testInputs = z_inputs(testIdx,:);

                trainResponses = obj.data.response(trainIdx);
                testResponse = obj.data.response(testIdx);
                
                [obj.parameterFits(f,:),~,exitflag] = fmincon(@(b) obj.calculateLogLik(b, trainInputs, trainResponses), obj.parameterStart(), [], [], [], [], obj.parameterBounds(1,:), obj.parameterBounds(2,:), [], options);
                
                if ~any(exitflag == [1,2])
                    obj.parameterFits(f,:) = nan(1,length(obj.parameterLabels));
                end
                
                phat = obj.calculatePhat(obj.parameterFits(f,:), testInputs);
                
                obj.p_hat(testIdx,1) = phat(testResponse);
            end
        end   
        
        function h=plotData(obj,varargin)
            if ~isempty(varargin)
                obj.data = getrow(obj.data,obj.data.laserIdx == varargin{1});
            end
            
            h=plotData@GLM(obj);
        end
        
        function plotFit(obj)
            %no laser
            subplot(1,2,1);
            h=obj.plotData(0);
            hold on;
            maxC = max(max(obj.data.contrast_cond));
            D.contrast_cond = [linspace(maxC,0,100)', zeros(100,1);
                zeros(100,1), linspace(0,maxC,100)'];
            D.laser = nan(200,1);
            evalC1d = D.contrast_cond(:,2) - D.contrast_cond(:,1);
            phat = obj.calculatePhat(obj.parameterFits,obj.ZINPUT(D));

            set(gca, 'ColorOrderIndex', 1);
            plot(h, evalC1d,phat);
            title('No laser');
            hold off;
            h=gca;
            
            hold off;
            h=gca;
            
            subplot(1,2,2);
            h=obj.plotData(max(obj.data.laserIdx));
            
            hold on;
            D.laser = ones(200,1);
            phat = obj.calculatePhat(obj.parameterFits,obj.ZINPUT(D));

            set(gca, 'ColorOrderIndex', 1);
            plot(h, evalC1d,phat);
            title('Laser');
            hold off;
            h=gca;
            
            hold off;
            h=gca;
        end
        
        function phat = calculatePhat(obj,testParams,inputs)
            if isempty(obj.ZL)
                error('Please set a model first using method setModel(...)');
            end

            zl = obj.ZL(testParams,inputs);
            zr = obj.ZR(testParams,inputs);
            pL = exp(zl)./(1+exp(zl)+exp(zr));
            pR = exp(zr)./(1+exp(zl)+exp(zr));
            pNG = 1 - pL - pR;
            
            phat = [pL pR pNG];

        end
    end
    
    methods (Access={?GLM})
        function logLik = calculateLogLik(obj,testParams,inputs,responses)
            phat = obj.calculatePhat(testParams, inputs);
            logLik = -sum(log( phat(sub2ind(size(phat), [1:length(responses)]', responses)) ));
        end
        
    end
end