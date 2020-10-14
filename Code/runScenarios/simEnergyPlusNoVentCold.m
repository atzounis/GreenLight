function gl = simEnergyPlusNoVentCold(location, simType, seasonLength, firstDay, fileLabel, mature, intensity)
% simEnergyPlus  --TO DO: DESCRIPTION--
% Runs the model with parameter values representing an HPS compartment in
% Bleiswijk, The Netherlands in 2010. Data is loaded from this trial and
% compared to the simulated data

% David Katzin, Wageningen University
% david.katzin@wur.nl
% david.katzin1@gmail.com


% location = 'ams';
% simType = 'hps';
% 
% seasonLength = 1; % season length in days
% firstDay = 300; % Beginning of season (days since January 1)

    absTol = 1e-6; % default is 1e-6; 1e-5 and even 1e-4 seem to also be ok
    relTol = 1e-3; % default is 1e-3; 1e-2 seems also fine

    disp(datetime('now'))
    tic;
    
    saveFile = true;
    if ~exist('fileLabel', 'var')
        fileLabel = '';
    end
    
    if strcmp(fileLabel,'')
            saveFile = false;
    end
    
    if ~exist('mature', 'var')
        mature = false;
    end
    
    if ~exist('intensity', 'var')
        intensity = 110*1.8/3; % == 66
    end

    [season, startTime] = loadEnergyPlusData(firstDay, seasonLength, location);

    gl = createGreenLightModel(season, startTime);
    feval(['set' upper(simType(1)) simType(2:end) 'Params'], gl); % set lamp params

    
    if strcmp(simType, 'led')
        setParam(gl, 'thetaLampMax', intensity);
        setParam(gl, 'capLamp', 10*1.8/3*intensity/66);
        setParam(gl, 'cHecLampAir', 2.3*1.8/3*intensity/66);
        setParam(gl, 'etaLampPar', 0.5);
        setParam(gl, 'zetaLampPar', 6);
        setParam(gl, 'etaLampCool', 0);
        
        setParam(gl, 'heatCorrection', 1);
        
        %% try more efficient LEDs
%         setParam(gl, 'etaLampPar', 0.67);
    end
    
    setParam(gl, 'co2SpDay', 1000);
    
    % KWIN says 17.5 night, 18.5 day, the values here are used to get
    % approximately that value
    setParam(gl, 'tSpNight', 18.5); 
    setParam(gl, 'tSpDay', 19.5);
    setParam(gl, 'rhMax', 85);
    setParam(gl, 'hAir', 5);
    setParam(gl, 'hGh', 6.4);
    
    setParam(gl, 'lampsOffYear', 105);
    setParam(gl, 'lampsOffSun', 400);
    
    % big boiler
    setParam(gl, 'pBoil', 300*gl.p.aFlr.val);
    
    %% Double the maximal harvest rate
    addAux(gl, 'mcLeafHar', smoothHar(gl.x.cLeaf, gl.p.cLeafMax, 1e4, 10e4));
    
    % Fruit harvest [mg{CH2O} m^{-2} s^{-1}]
    addAux(gl, 'mcFruitHar', smoothHar(gl.x.cFruit, gl.p.cFruitMax, 1e4, 10e4));
    
    
    %% Start with a mature crop
    if mature
        setVal(gl.x.cFruit, 2.8e5);
        setVal(gl.x.cLeaf, 0.9e5);
        setVal(gl.x.cStem, 2.5e5);
        setVal(gl.x.tCanSum, 3000);
    end
   
    
    %% Increase outdoor temperature by 2�C
%     gl.d.tOut.val(:,2) = gl.d.tOut.val(:,2)+2;

    %% Increase RH set point by 10%
%     setParam(gl, 'rhMax', 95);

    %% Screens are only controlled by temperature
%     gl.u.thScr = min(gl.a.thScrCold, gl.a.thScrHeat);

    %% Do not vent if it's cold out
    addAux(gl, 'coldOut', gl.d.tOut <= 5);
    gl.u.roof = gl.u.roof.*(1-gl.a.coldOut);
    setVal(gl.u.roof, []);

    %% Solve
    options = odeset('AbsTol', absTol, 'RelTol', relTol);
    solveFromFile(gl, 'ode15s', options);

    gl = changeRes(gl,300); % set resolution of trajectories at 5 minutes

    startTime = datestr(startTime);
    startTime = startTime(1:11);

    runTime = toc;
    fprintf('Elapsed time is %f seconds.\n', runTime);
    
    if saveFile
        save(['energyPlus_' fileLabel '_' location '_' simType '_' startTime '_' num2str(seasonLength) 'days']);
    end
    
    disp(datetime('now'))
    
    beep
end

%% temp
function de = smoothHar(processVar, cutOff, smooth, maxRate)
% Define a smooth function for harvesting (leaves, fruit, etc)
% processVar - the DynamicElement to be controlled
% cutoff     - the value at which the processVar should be harvested
% smooth     - smoothing factor. The rate will go from 0 to max at
%              a range with approximately this width
% maxRate    - the maximum harvest rate

    de = maxRate./(1+exp(-(processVar-cutOff)*2*log(100)./smooth));

end