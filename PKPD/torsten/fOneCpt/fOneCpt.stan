## fOneCpt.stan: example to test mixed solver
## Does NOT use Torsten

functions {
  real[] feedbackODE (real t,
			                real[] x,
			                real[] parms,
			                real[] rdummy,
			                int[] idummy) {
    ## PK variables
    real CL = parms[1];
    real VC = parms[2];
    real ka = parms[3];
    real k10 = CL / VC;
    real conc;
    real Edrug;
    
    ## PD variables
    real MTT = parms[4];
    real circ0 = parms[5];
    real alpha = parms[6];
    real gamma = parms[7];
    real ktr = 4 / MTT;
    real prol = x[3] + circ0;
    real transit = x[4] + circ0;
    real circ = fmax(machine_precision(), x[5] + circ0);
    
    real dxdt[5];

    dxdt[1] = -ka * x[1];
    dxdt[2] = ka * x[1] - k10 * x[2];
    conc = x[2] / VC;
    Edrug = alpha * conc;
  
    dxdt[3] = ktr * prol * ((1 - Edrug) * ((circ0 / circ)^gamma) - 1);
    dxdt[4] = ktr * (prol - transit);
    dxdt[5] = ktr * (transit - circ);

    return dxdt;
	}

  real[] feedbackModel1(real t0, real[]  t, real[] init,
                        real amt, int cmt, int evid,
                        real[] parms,
                        real[] rdummy, int[] idummy) {
    real x[5];  //  = rep_array(0, 5); Don't need defaults...
    real temp[1, 5];

    if (t0 == t[1]) x = init;
    else {
      temp = integrate_ode_rk45(feedbackODE, init, t0, t, parms,
                                rdummy, idummy);
      x = to_array_1d(temp);
    }
    
    if (evid == 1) x[cmt] = x[cmt] + amt;
    
    return x;
  }
  
  matrix feedbackModel(real[] time, real[] amt, int[] cmt, int[] evid,
                       real[] parms, real[] rdummy, int[] idummy) {
    real init[5];
    int nt = size(time);
    matrix[nt, 5] pred;
    real t0 = time[1];
    
    init = rep_array(0, 5);
    
    for (i in 1:nt) {
      init = feedbackModel1(time[max(1, i - 1)], time[i:i], init, amt[i], cmt[i],
                            evid[i], parms, rdummy, idummy);
      for (j in 1:5) pred[i, j] = init[j];
    }
    return pred;
  }
}

data{
  int<lower = 1> nt;
  int<lower = 1> nObsPK;
  int<lower = 1> nObsPD;
  int<lower = 1> iObsPK[nObsPK];
  int<lower = 1> iObsPD[nObsPD];
  real<lower = 0> amt[nt];
  real<lower = 0> rate[nt];
  int<lower = 1> cmt[nt];
  int<lower = 0> evid[nt];
  real<lower = 0> time[nt];
  real<lower = 0> ii[nt];
  int<lower = 0> addl[nt];
  int<lower = 0> ss[nt];
  vector<lower = 0>[nObsPK] cObs;
  vector<lower = 0>[nObsPD] neutObs;
  
  ## data for priors
  real<lower = 0> circ0Prior;
  real<lower = 0> circ0PriorCV;
  real<lower = 0> mttPrior;
  real<lower = 0> mttPriorCV;
  real<lower = 0> gammaPrior;
  real<lower = 0> gammaPriorCV;
  real<lower = 0> alphaPrior;
  real<lower = 0> alphaPriorCV;
  
  real<lower = 0> CLPrior;
  real<lower = 0> CLPriorCV;
  real<lower = 0> VCPrior;
  real<lower = 0> VCPriorCV;
  real<lower = 0> kaPrior;
  real<lower = 0> kaPriorCV;
}

transformed data{
  vector[nObsPK] logCObs = log(cObs);
  vector[nObsPD] logNeutObs = log(neutObs);
  int nParms = 7;
  int nCmt = 5;
  real rdummy[0];
  int idummy[0];
  real biovar[nCmt];
  real tlag[nCmt];
  
  for (i in 1:nCmt) {
    biovar[i] = 1;
    tlag[i] = 0;
  }
}

parameters {
  real<lower = 0> CL;
  real<lower = 0> VC;
  real<lower = 0> ka;
  real<lower = 0> mtt;
  real<lower = 0> circ0;
  real<lower = 0> alpha;
  real<lower = 0> gamma;
  real<lower = 0> sigma;
  real<lower = 0> sigmaNeut;
}

transformed parameters {
  vector[nt] cHat;
  vector[nObsPK] cHatObs;
  vector[nt] neutHat;
  vector<lower = 0>[nObsPD] neutHatObs;
  real theta[nParms];  # ODE parameters
  matrix[nt, nCmt] x;
  
  theta[1] = CL;
  theta[2] = VC;
  theta[3] = ka;
  theta[4] = mtt;
  theta[5] = circ0;
  theta[6] = alpha;
  theta[7] = gamma;
  
  x = feedbackModel(time, amt, cmt, evid, theta, rdummy, idummy);
  
  cHat = x[ , 2] / VC;
  neutHat = x[ , 5] + circ0;

  cHatObs = cHat[iObsPK];
  neutHatObs = neutHat[iObsPD];
}

model{
  ## Priors
  CL ~ lognormal(log(CLPrior), CLPriorCV);
  VC ~ lognormal(log(VCPrior), VCPriorCV);
  ka ~ lognormal(log(kaPrior), kaPriorCV);
  sigma ~ cauchy(0, 1);
  
  mtt ~ lognormal(log(mttPrior), mttPriorCV);
  circ0 ~ lognormal(log(circ0Prior), circ0PriorCV);
  alpha ~ lognormal(log(alphaPrior), alphaPriorCV);
  gamma ~ lognormal(log(gammaPrior), gammaPriorCV);
  sigmaNeut ~ cauchy(0, 1);

  ## observed data likelihood
  logCObs ~ normal(log(cHatObs), sigma);
  logNeutObs ~ normal(log(neutHatObs), sigmaNeut);
}

generated quantities {
  real cObsPred[nObsPK];
  real neutPred[nObsPD];
  
  for (i in 1:nObsPK)
    cObsPred[i] = exp(normal_rng(logCObs[i], sigma));
    
  for (i in 1:nObsPD)
    neutPred[i] = exp(normal_rng(logNeutObs[i], sigma));
}



