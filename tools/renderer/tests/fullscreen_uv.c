/* Numeric offscreen test of the game's fullscreen VS/PS and captured vertices. */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>
#include <float.h>
#include <math.h>
static void *read_file(const wchar_t *root,const wchar_t *name,UINT *size) {
 wchar_t path[32768];swprintf(path,32768,L"%ls\\%ls",root,name);FILE *f=_wfopen(path,L"rb");if(!f)return NULL;
 fseek(f,0,SEEK_END);*size=ftell(f);rewind(f);void *d=malloc(*size);fread(d,1,*size,f);fclose(f);return d;
}
#define CHECK(op) do{HRESULT h=(op);if(FAILED(h)){fprintf(stderr,"line=%d hr=%08lx\n",__LINE__,(unsigned long)h);return 2;}}while(0)
int wmain(int argc,wchar_t **argv){
 if(argc!=5)return 1;UINT size;void *code=read_file(argv[1],argv[2],&size);if(!code)return 1;
 ID3D11Device *dev=NULL;ID3D11DeviceContext *ctx=NULL;CHECK(D3D11CreateDevice(NULL,D3D_DRIVER_TYPE_HARDWARE,NULL,0,NULL,0,D3D11_SDK_VERSION,&dev,NULL,&ctx));
 ID3D11VertexShader *vs=NULL;CHECK(ID3D11Device_CreateVertexShader(dev,code,size,NULL,&vs));
 D3D11_INPUT_ELEMENT_DESC elements[]={{"POSITION",0,DXGI_FORMAT_R32G32B32A32_FLOAT,0,0,0,0},{"TEXCOORD",0,DXGI_FORMAT_R32G32B32_FLOAT,0,16,0,0}};
 ID3D11InputLayout *layout=NULL;CHECK(ID3D11Device_CreateInputLayout(dev,elements,2,code,size,&layout));free(code);
 code=read_file(argv[1],argv[3],&size);if(!code)return 1;ID3D11PixelShader *ps=NULL;CHECK(ID3D11Device_CreatePixelShader(dev,code,size,NULL,&ps));free(code);
 void *vertices=read_file(argv[1],argv[4],&size);if(!vertices || size<112)return 1;
 float pixels[32*32*4];for(int y=0;y<32;y++)for(int x=0;x<32;x++){int k=(y*32+x)*4;pixels[k]=(x+.5f)/32;pixels[k+1]=(y+.5f)/32;pixels[k+2]=.25f;pixels[k+3]=1;}
 D3D11_TEXTURE2D_DESC td={0};td.Width=td.Height=32;td.MipLevels=td.ArraySize=td.SampleDesc.Count=1;td.Format=DXGI_FORMAT_R32G32B32A32_FLOAT;td.BindFlags=D3D11_BIND_SHADER_RESOURCE;td.Usage=D3D11_USAGE_IMMUTABLE;
 D3D11_SUBRESOURCE_DATA init={pixels,32*16,0};ID3D11Texture2D *source=NULL;CHECK(ID3D11Device_CreateTexture2D(dev,&td,&init,&source));
 ID3D11ShaderResourceView *srv=NULL;CHECK(ID3D11Device_CreateShaderResourceView(dev,(ID3D11Resource *)source,NULL,&srv));
 td.Usage=D3D11_USAGE_DEFAULT;td.BindFlags=D3D11_BIND_RENDER_TARGET;ID3D11Texture2D *target=NULL;CHECK(ID3D11Device_CreateTexture2D(dev,&td,NULL,&target));
 ID3D11RenderTargetView *rtv=NULL;CHECK(ID3D11Device_CreateRenderTargetView(dev,(ID3D11Resource *)target,NULL,&rtv));
 td.Usage=D3D11_USAGE_STAGING;td.BindFlags=0;td.CPUAccessFlags=D3D11_CPU_ACCESS_READ;ID3D11Texture2D *stage=NULL;CHECK(ID3D11Device_CreateTexture2D(dev,&td,NULL,&stage));
 UINT indices[]={0,1,2,0,2,3};D3D11_BUFFER_DESC bd={0};bd.Usage=D3D11_USAGE_IMMUTABLE;bd.ByteWidth=sizeof(indices);bd.BindFlags=D3D11_BIND_INDEX_BUFFER;init.pSysMem=indices;
 ID3D11Buffer *ib=NULL;CHECK(ID3D11Device_CreateBuffer(dev,&bd,&init,&ib));
 D3D11_RASTERIZER_DESC rd={0};rd.FillMode=D3D11_FILL_SOLID;rd.CullMode=D3D11_CULL_NONE;rd.DepthClipEnable=TRUE;ID3D11RasterizerState *rs=NULL;CHECK(ID3D11Device_CreateRasterizerState(dev,&rd,&rs));
 D3D11_SAMPLER_DESC sd={0};sd.Filter=D3D11_FILTER_MIN_MAG_MIP_POINT;sd.AddressU=sd.AddressV=sd.AddressW=D3D11_TEXTURE_ADDRESS_CLAMP;sd.MaxLOD=FLT_MAX;sd.ComparisonFunc=D3D11_COMPARISON_NEVER;
 ID3D11SamplerState *sampler=NULL;CHECK(ID3D11Device_CreateSamplerState(dev,&sd,&sampler));
 ID3D11DeviceContext_IASetInputLayout(ctx,layout);ID3D11DeviceContext_IASetPrimitiveTopology(ctx,D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);ID3D11DeviceContext_IASetIndexBuffer(ctx,ib,DXGI_FORMAT_R32_UINT,0);
 ID3D11DeviceContext_VSSetShader(ctx,vs,NULL,0);ID3D11DeviceContext_PSSetShader(ctx,ps,NULL,0);ID3D11DeviceContext_PSSetShaderResources(ctx,0,1,&srv);ID3D11DeviceContext_PSSetSamplers(ctx,0,1,&sampler);
 ID3D11DeviceContext_OMSetRenderTargets(ctx,1,&rtv,NULL);ID3D11DeviceContext_RSSetState(ctx,rs);D3D11_VIEWPORT vp={0,0,32,32,0,1};ID3D11DeviceContext_RSSetViewports(ctx,1,&vp);
 for(int pass=0;pass<4;pass++){
  ((float *)vertices)[3]=(pass&1)?1:0;((float *)vertices)[5]=(pass&2)?1:0;
  bd.ByteWidth=112;bd.BindFlags=D3D11_BIND_VERTEX_BUFFER;init.pSysMem=vertices;ID3D11Buffer *vb=NULL;CHECK(ID3D11Device_CreateBuffer(dev,&bd,&init,&vb));
  UINT stride=28,offset=0;ID3D11DeviceContext_IASetVertexBuffers(ctx,0,1,&vb,&stride,&offset);float clear[]={-1,-1,-1,-1};ID3D11DeviceContext_ClearRenderTargetView(ctx,rtv,clear);
  ID3D11DeviceContext_DrawIndexed(ctx,6,0,0);ID3D11DeviceContext_CopyResource(ctx,(ID3D11Resource *)stage,(ID3D11Resource *)target);D3D11_MAPPED_SUBRESOURCE map={0};CHECK(ID3D11DeviceContext_Map(ctx,(ID3D11Resource *)stage,0,D3D11_MAP_READ,0,&map));
  double max_error=0;int mismatches=0;for(int y=0;y<32;y++)for(int x=0;x<32;x++){
   float *v=(float *)((char *)map.pData+y*map.RowPitch)+x*4;float *e=pixels+(y*32+x)*4;double error=fmax(fabs(v[0]-e[0]),fabs(v[1]-e[1]));if(error>max_error)max_error=error;if(error>1.f/32)mismatches++;
  }
  printf("pass=%d pixels=1024 mismatches=%d max_error=%f\n",pass,mismatches,max_error);
  ID3D11DeviceContext_Unmap(ctx,(ID3D11Resource *)stage,0);ID3D11Buffer_Release(vb);
 }
 free(vertices);ID3D11DeviceContext_ClearState(ctx);ID3D11RasterizerState_Release(rs);ID3D11SamplerState_Release(sampler);ID3D11Buffer_Release(ib);ID3D11Texture2D_Release(stage);ID3D11RenderTargetView_Release(rtv);
 ID3D11Texture2D_Release(target);ID3D11ShaderResourceView_Release(srv);ID3D11Texture2D_Release(source);ID3D11InputLayout_Release(layout);ID3D11VertexShader_Release(vs);ID3D11PixelShader_Release(ps);ID3D11DeviceContext_Release(ctx);ID3D11Device_Release(dev);return 0;
}
