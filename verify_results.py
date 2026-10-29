"""verify_results.py - independent check of one OPT_ONE_SENS v3 scenario (.mat v7.3 with RES).
Usage: python verify_results.py path/to/results_heavy.mat     (needs numpy, h5py)
Re-computes every constraint, total emissions and total discounted cost from the
solution (U, K, Z, ChB, Dump, E, C) and the inputs stored in RES.P, then prints a
year-by-year table. Assumes beta = 1 in the reserve margin (edit the C13 line if not).
"""
import h5py, numpy as np
import sys
f=h5py.File(sys.argv[1] if len(sys.argv)>1 else 'results_heavy.mat','r'); R=f['RES']
G=lambda p: np.array(R[p][()])
F=lambda p: float(np.array(R[p][()]).ravel()[0])
s_obj=''.join(chr(int(x)) for x in np.array(R['P/OBJECTIVE'][()]).ravel())
U=G('U'); K=G('K'); Z=G('Z'); ChB=G('ChB').ravel(); Dump=G('Dump').ravel(); E=G('E').ravel(); C=G('C').ravel()
D=G('P/Demand').ravel(); cf=G('P/cf').ravel(); cS=G('P/cSolar_t').ravel(); cB=G('P/cBatt_t').ravel()
c=G('P/c').ravel(); p=G('P/p').ravel(); Lt=G('P/lifeTime').ravel().astype(int); CRF=G('P/CRF').ravel()
Cap=G('P/Capex'); Op=G('P/Opex'); Var=G('P/Var')   # [source, year]
df=G('P/df_yearly').ravel(); leg=G('P/legacyYear').T   # [source, year]
ramp=G('P/rampYear').T; maxRamp=G('meta/maxRamp').ravel()
area=F('meta/maxAreaSolar'); budget=F('meta/maxCost'); EF=F('P/EmissionsFactor')
T=len(D); yl=8760; nY=28; n=5; a=0.0075; H=4; ec,ed=0.95,0.90
res={}
def rep(name,val,tol,unit=''):
    ok = val<=tol; print(f"[{'PASS' if ok else 'FAIL'}] {name}: {val:.3g} {unit} (tol {tol:g})"); return ok
print('Scenario: emissions-min, budget %.0f bn NIS, land %.0f km2'%(budget/1e9,area))
rep('C1 demand balance max |sum U - D|', np.abs(U.sum(1)-D).max(), 1e-3,'MW')
rep('C2 solar split max |U2+ChB+Dump-cf*K2|', np.abs(U[:,1]+ChB+Dump-cf*K[:,1]).max(),1e-3,'MW')
rep('Non-negativity (most negative value)', -min(U.min(),K.min(),Z.min(),ChB.min(),Dump.min(),E.min()), 1e-4)
rep('C2b U<=K for nuc/gas/coal', max((U[:,i]-K[:,i]).max() for i in [0,2,3]),1e-3,'MW')
rep('C11 batt discharge<=K5, charge<=K5', max((U[:,4]-K[:,4]).max(),(ChB-K[:,4]).max()),1e-3,'MW')
Eprev=np.concatenate([[0.0],E[:-1]])
rep('C9 SOC balance', np.abs(E-Eprev-ec*ChB+U[:,4]/ed).max(),1e-3,'MWh')
rep('C10 E<=4*K5', (E-H*K[:,4]).max(),1e-3,'MWh')
rep('C11b discharge<=0.9*E(t-1)', (U[:,4]-ed*Eprev).max(),1e-3,'MW')
rep('Headroom 0.95*ChB<=4K5-E(t-1)', (ec*ChB-(H*K[:,4]-Eprev)).max(),1e-3,'MWh')
# Z only at year ends, none in final year
mask=np.ones(T,bool); mask[np.arange(1,nY)*yl-1]=False
rep('C4 builds only at year-end hours (2023-2049)', np.abs(Z[mask,1:]).max(),1e-6,'blocks')
# C3 dynamics
err=0
for i in range(n):
    Kp=np.concatenate([[0.0],K[:-1,i]]); dl=np.zeros(T)
    dl[0]=leg[i,0]
    for y in range(1,nY): dl[y*yl-1]=leg[i,y]-leg[i,y-1]
    ret=np.zeros(T); Lh=Lt[i]*yl
    if Lh<T: ret[Lh:]=Z[:T-Lh,i]
    err=max(err,np.abs(K[:,i]-Kp-p[i]*Z[:,i]+p[i]*ret-dl).max())
rep('C3 capacity dynamics incl. legacy steps and retirement',err,1e-3,'MW')
# build limits
v=0
for i in range(n):
    for y in range(1,nY):
        lim=maxRamp[i] if np.isnan(ramp[i,y-1]) else min(maxRamp[i],ramp[i,y-1])
        v=max(v,p[i]*Z[y*yl-1,i]-lim)
rep('C8 build-rate limits',v,1e-3,'MW')
rep('C6 land a*K2<=cap', (a*K[:,1]).max()-area,1e-6,'km2')
# C13 reserve
v=-1e9
for y in range(nY):
    rng=np.arange(y*yl,(y+1)*yl); dd=D[rng]; cc=cf[rng]
    top=rng[np.argsort(-dd,kind='stable')[:10]]
    z=np.where(cc==0)[0]; topn=rng[z[np.argsort(-dd[z],kind='stable')[:10]]]
    for t in np.unique(np.concatenate([top,topn])):
        lhs=K[t,0]+K[t,2]+K[t,3]+1.2*U[t,1]+1.0*K[t,4]; v=max(v,1.2*D[t]-lhs)
rep('C13 reserve margin (beta=1) worst shortfall',v,1e-3,'MW')
# legacy checks
y=lambda Y:Y-2023
print('Coal K end-2029 hour onwards max: %.3g MW; coal gen 2030+: %.3g MWh'%(K[y(2030)*yl-1:,3].max(),U[y(2030)*yl:,3].sum()))
# emissions
em=(c[0]*U[:,0]+c[2]*U[:,2]+c[3]*U[:,3]+cS*cf*K[:,1]+cB*U[:,4]).sum()
emRES=F('TotalEmissions_AllYears'); obj=F('result/objval')
epsC=F('P/EPS_COST') if 'EPS_COST' in R['P'] else 0.0      # tie-breaking term (v4)
if s_obj=='emissions': obj-=epsC*C[-1]
print('Emissions: recomputed %.6e | KPI %.6e | objective %.6e t'%(em,emRES,obj))
rep('Emissions recomputed vs objective minus tie-break term (rel)',abs(em/obj-1),1e-6)
# cost
capex=0; fom=0; var=0; ext=0
for i in range(n):
    for yy in range(1,nY):
        mw=p[i]*Z[yy*yl-1,i]
        if mw>0:
            yLast=min(nY,yy+Lt[i]-1)
            capex+=Cap[i,yy-1]*mw*CRF[i]*df[yy-1:yLast].sum()
    for yy in range(1,nY+1):
        fom+=Op[i,yy-1]*K[yy*yl-2,i]*df[yy-1]
yidx=np.arange(T)//yl
dft=df[yidx]
var=(Var[1,yidx]*cf*K[:,1]*dft).sum()+sum((Var[i,yidx]*U[:,i]*dft).sum() for i in [0,2,3,4])
ext=EF*((c[0]*U[:,0]+c[2]*U[:,2]+c[3]*U[:,3]+cS*cf*K[:,1]+cB*U[:,4])*dft).sum()
tot=capex+fom+var+ext
print('Cost recomputed: CAPEX %.4g + FOM %.4g + VAR %.4g + carbon %.4g = %.6e NIS'%(capex,fom,var,ext,tot))
print('Model C(T)*1e6 = %.6e ; KPI TotalCost = %.6e ; budget %.3e'%(C[-1]*1e6,F('TotalCost_AllYears'),budget))
rep('Cost recomputed vs C(T) (rel)',abs(tot/(C[-1]*1e6)-1),1e-6)
print('KPI CAPEX/OPEX/ext:',F('TotalCAPEX_AllYears'),F('TotalOPEX_AllYears'),F('TotalExternalities_AllYears'))

import numpy as np
yl=8760
print(' year  D_TWh  RE%  sol% gas% coal% bat%  curt%  K_sol K_gas K_coal K_bat  build_sol build_bat build_gas  bat_cyc gasCF%')
for yy in range(28):
    r=slice(yy*yl,(yy+1)*yl); d=D[r].sum()
    g=U[r].sum(0); re=(g[0]+g[1]+g[4])/d*100
    pot=(cf[r]*K[r,1]).sum(); curt=Dump[r].sum()/pot*100
    k=K[(yy+1)*yl-2]   # level during the year
    b=p*Z[(yy+1)*yl-1] if yy<27 else np.zeros(5)
    cyc=g[4]/max(1,k[4]*4)
    gcf=g[2]/max(1,k[2]*8760)*100
    print(f"{2023+yy} {d/1e6:6.1f} {re:5.1f} {g[1]/d*100:5.1f} {g[2]/d*100:4.1f} {g[3]/d*100:5.1f} {g[4]/d*100:4.1f} {curt:6.1f} {k[1]/1e3:6.1f} {k[2]/1e3:5.1f} {k[3]/1e3:6.1f} {k[4]/1e3:5.1f}  {b[1]/1e3:8.2f} {b[4]/1e3:9.2f} {b[2]/1e3:9.2f} {cyc:8.0f} {gcf:6.1f}")
lim_s=[min(maxRamp[1],ramp[1,i]) for i in range(27)]
print('solar build at limit every year:', all(abs(p[1]*Z[(i+1)*yl-1,1]-lim_s[i])<1 for i in range(27)))
lim_b=[min(maxRamp[4],ramp[4,i]) for i in range(27)]
print('battery build at limit years:', [2023+i for i in range(27) if abs(p[4]*Z[(i+1)*yl-1,4]-lim_b[i])<1])
