if [ -z $1 ]; then
    SHADER_NAME=triangle
else
    SHADER_NAME=$1
fi

SHADERCROSS=../../soft/SDL_shadercross/build/shadercross
SHADER_SRC=src/shaders/src
SHADER_SPV_OUT=src/shaders/spv
SHADER_MSL_OUT=src/shaders/msl
SHADER_DXIL_OUT=src/shaders/dxil
SHADER_JSON_OUT=src/shaders/json

glslc -fshader-stage=vertex $SHADER_SRC/$SHADER_NAME.vert.glsl -o $SHADER_SPV_OUT/$SHADER_NAME.vert.spv
glslc -fshader-stage=fragment $SHADER_SRC/$SHADER_NAME.frag.glsl -o $SHADER_SPV_OUT/$SHADER_NAME.frag.spv

$SHADERCROSS $SHADER_SPV_OUT/$SHADER_NAME.vert.spv --source SPIRV --dest MSL --stage vertex --entrypoint main -o $SHADER_MSL_OUT/$SHADER_NAME.vert.msl
$SHADERCROSS $SHADER_SPV_OUT/$SHADER_NAME.frag.spv --source SPIRV --dest MSL --stage fragment --entrypoint main -o $SHADER_MSL_OUT/$SHADER_NAME.frag.msl

$SHADERCROSS $SHADER_SPV_OUT/$SHADER_NAME.vert.spv --source SPIRV --dest DXIL --stage vertex --entrypoint main -o $SHADER_DXIL_OUT/$SHADER_NAME.vert.dxil
$SHADERCROSS $SHADER_SPV_OUT/$SHADER_NAME.frag.spv --source SPIRV --dest DXIL --stage fragment --entrypoint main -o $SHADER_DXIL_OUT/$SHADER_NAME.frag.dxil

$SHADERCROSS $SHADER_SPV_OUT/$SHADER_NAME.vert.spv --source SPIRV --dest JSON --stage vertex --entrypoint main -o $SHADER_JSON_OUT/$SHADER_NAME.vert.json
$SHADERCROSS $SHADER_SPV_OUT/$SHADER_NAME.frag.spv --source SPIRV --dest JSON --stage fragment --entrypoint main -o $SHADER_JSON_OUT/$SHADER_NAME.frag.json

