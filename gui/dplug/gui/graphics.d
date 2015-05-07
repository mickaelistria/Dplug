module dplug.gui.graphics;

import ae.utils.graphics;
import dplug.plugin.client;
import dplug.plugin.graphics;

import dplug.gui.window;
import dplug.gui.mipmap;
import dplug.gui.boxlist;
import dplug.gui.toolkit.context;
import dplug.gui.toolkit.element;

// A GUIGraphics is the interface between a plugin client and a IWindow.
// It is also an UIElement and the root element of the plugin UI hierarchy.
// You have to derive it to have a GUI.
// It dispatches window events to the GUI hierarchy.
class GUIGraphics : UIElement, IGraphics
{
    this(int initialWidth, int initialHeight)
    {
        _uiContext = new UIContext();
        super(_uiContext);

        _windowListener = new WindowListener();

        _window = null;
        _askedWidth = initialWidth;
        _askedHeight = initialHeight;       
    }

    // Graphics implementation

    override void openUI(void* parentInfo)
    {
        // We create this window each time.
        _window = createWindow(parentInfo, _windowListener, _askedWidth, _askedHeight);
        reflow(box2i(0, 0, _askedWidth, _askedHeight));
    }

    override void closeUI()
    {
        // Destroy window.
        _window.terminate();
    }

    override int getGUIWidth()
    {
        return _askedWidth;
    }

    override int getGUIHeight()
    {
        return _askedHeight;
    }


    // This nested class is only here to avoid name conflicts between 
    // UIElement and IWindowListener methods :|
    class WindowListener : IWindowListener
    {
        override bool onMouseClick(int x, int y, MouseButton mb, bool isDoubleClick)
        {
            return this.outer.mouseClick(x, y, mb, isDoubleClick);
        }

        override bool onMouseRelease(int x, int y, MouseButton mb)
        {
            this.outer.mouseRelease(x, y, mb);
            return true;
        }

        override bool onMouseWheel(int x, int y, int wheelDeltaX, int wheelDeltaY)
        {
            return this.outer.mouseWheel(x, y, wheelDeltaX, wheelDeltaY);
        }

        override void onMouseMove(int x, int y, int dx, int dy)
        {
            this.outer.mouseMove(x, y, dx, dy);
        }

        override bool onKeyDown(Key key)
        {
            // Sends the event to the last clicked element first
            if (_uiContext.focused !is null)
                if (_uiContext.focused.onKeyDown(key))
                    return true;

            // else to all Elements
            return keyDown(key);
        }

        override bool onKeyUp(Key key)
        {
            // Sends the event to the last clicked element first
            if (_uiContext.focused !is null)
                if (_uiContext.focused.onKeyUp(key))
                    return true;
            // else to all Elements
            return keyUp(key);
        }

        override void markRectangleDirty(box2i dirtyRect)
        {
            setDirty(dirtyRect);
        }

        override box2i getDirtyRectangle()
        {
            // TODO: cache for areas to update to share with onDraw?

            // Get sorted draw list
            UIElement[] elemsToDraw = getDrawList();

            // Get areas to update
            _areasToUpdate.length = 0;
            foreach(elem; elemsToDraw)
                _areasToUpdate ~= elem.dirtyRect();

            return _areasToUpdate.boundingBox();
        }

        override void onResized(int width, int height)
        {
            _askedWidth = width;
            _askedHeight = height;

            reflow(box2i(0, 0, _askedWidth, _askedHeight));

            _diffuseMap.size(4, width, height);
            _depthMap.size(4, width, height);
        }

        // an image you have to draw to, or return that nothing has changed
        override box2i[] onDraw(ImageRef!RGBA wfb)
        {
            // TODO: cache for areas to update to share with getDirtyRectangle?

            // Get sorted draw list
            UIElement[] elemsToDraw = getDrawList();

            // Get areas to update
            _areasToUpdate.length = 0;
            foreach(elem; elemsToDraw)
                _areasToUpdate ~= elem.dirtyRect();

            // Split boxes to avoid overdraw
            _areasToUpdate.boxes = _areasToUpdate.removeOverlappingAreas();

            // Render required areas in diffuse and depth maps, base level
            foreach(elem; elemsToDraw)
                elem.render(_diffuseMap.levels[0].toRef(), _depthMap.levels[0].toRef());

            box2i[] areas = _areasToUpdate.boxes[];

            // Recompute mipmaps in updated areas
            foreach(area; areas)
            {
                _diffuseMap.generateMipmaps(area);
                _depthMap.generateMipmaps(area);
            }

            // Clear dirty state in the whole GUI since after this draw everything 
            // will be up-to-date.
            clearDirty();

            // Composite GUI
            compositeGUI(wfb, areas);

            // Return non-overlapping areas to update on screen
            return areas;
        }

        override void onMouseCaptureCancelled()
        {
            // Stop an eventual drag operation
            _uiContext.stopDragging();
        }
    }


protected:
    UIContext _uiContext;

    WindowListener _windowListener;

    // An interface to the underlying window
    IWindow _window;

    BoxList _areasToUpdate;

    int _askedWidth = 0;
    int _askedHeight = 0;

    Mipmap _diffuseMap;
    Mipmap _depthMap;

    // compose lighting effects
    // takes output image and non-overlapping areas as input
    void compositeGUI(ImageRef!RGBA wfb, box2i[] areas)
    {
        ImageRef!RGBA skybox = context().skybox.toRef();
/*
        alias diffuse = _diffuseMap;
        alias depth = _depthMap;
*/        
        int w = _diffuseMap.levels[0].w;
        int h = _diffuseMap.levels[0].h;

        foreach(area; areas)
        {
            for (int j = area.min.y; j < area.max.y; ++j)
            {
                // clamp to existing lines
                int[5] line_index = void;
                for (int l = 0; l < 5; ++l)
                    line_index[l] = clamp(j - 2 + l, 0, h - 1);

                RGBA[][5] depth_scan = void;
                for (int l = 0; l < 5; ++l)
                    depth_scan[l] = _depthMap.levels[0].scanline(line_index[l]);


                for (int i = area.min.x; i < area.max.x; ++i)
                {
                    // clamp to existing columns
                    int[5] col_index = void;
                    for (int k = 0; k < 5; ++k)
                        col_index[k] = clamp(i - 2 + k, 0, w - 1);

                    // Get depth for a 5x5 patch
                    ubyte[5][5] depthPatch = void;
                    for (int l = 0; l < 5; ++l)
                    {
                        for (int k = 0; k < 5; ++k)
                        {
                            depthPatch.ptr[l].ptr[k] = depth_scan.ptr[l].ptr[col_index[k]].r;
                        }
                    }

                    // compute normal
                    float sx = depthPatch[1][0] + depthPatch[1][1] + depthPatch[2][0] + depthPatch[2][1] + depthPatch[3][0] + depthPatch[3][1]
                             - ( depthPatch[1][3] + depthPatch[1][4] + depthPatch[2][3] + depthPatch[2][4] + depthPatch[3][3] + depthPatch[3][4] );

                    float sy = depthPatch[3][1] + depthPatch[4][1] + depthPatch[3][2] + depthPatch[4][2] + depthPatch[3][3] + depthPatch[4][3]
                             - ( depthPatch[0][1] + depthPatch[1][1] + depthPatch[0][2] + depthPatch[1][2] + depthPatch[0][3] + depthPatch[1][3] );

                    enum float sz = 16.0f * 9.0f;

                    vec3f normal = vec3f(sx, sy, sz).normalized;


                    

                    RGBA imaterialDiffuse = _diffuseMap.levels[0][i, j];  
                    vec3f materialDiffuse = vec3f(imaterialDiffuse.r / 255.0f, imaterialDiffuse.g / 255.0f, imaterialDiffuse.b / 255.0f);



                    vec3f color = vec3f(0.0f);

                    // Combined color bleed and ambient occlusion!
                    // TODO: accelerate this with mipmaps
                    
                    vec3f colorBleed = 0;
                    
                    {
                        int bleedWidth = 7;
                        int redAccum = 0;
                        int greenAccum = 0;
                        int blueAccum = 0;

                        for (int l = -bleedWidth; l <= bleedWidth; ++l)
                        {
                            int y = clamp(j + l, 0, h - 1);
                            RGBA[] scanDepth = _depthMap.levels[0].scanline(y);
                            RGBA[] scanDiffuse = _diffuseMap.levels[0].scanline(y);

                            // repeat AO for borders
                        

                            for (int k = -bleedWidth; k <= bleedWidth; ++k)                        
                            {
                                int x = clamp(i + k, 0, w - 1);                            

                                RGBA diffuseRGBA = scanDiffuse.ptr[x];  
                                int depthSample = scanDepth.ptr[x].r;

                                redAccum += diffuseRGBA.r * depthSample;
                                greenAccum += diffuseRGBA.g * depthSample;
                                blueAccum += diffuseRGBA.b * depthSample;
                            }

                        }
                        enum float totalWeight = (7 * 2 + 1) * (7 * 2 + 1) * 255.0f * 255.0f;
                        enum float one_on_totalWeight = 1.0f / totalWeight;

                        colorBleed = vec3f(redAccum * one_on_totalWeight, greenAccum * one_on_totalWeight, blueAccum * one_on_totalWeight);
                    }
                    

                    // cast shadows

                    int samples = 10;
                    float lightPassed = 0.0f;
                    float totalWeight = 0.0f;
                    float weight = 1.0f;
                    for (int l = 1; l <= samples; ++l)
                    {
                        int x = clamp(i + l, 0, w - 1);
                        int y = clamp(j - l, 0, h - 1);
                        float z = _depthMap.levels[0][i, j].r + l;

                        float diff = z - _depthMap.levels[0][x, y].r;

                        lightPassed += smoothStep!float(-40.0f, 20.0f, diff) * weight;
                        totalWeight += weight;
                        weight *= 0.78f;
                    }
                    lightPassed /= totalWeight;
                    vec3f keylightColor = vec3f(0.54f, 0.50f, 0.46f)* 0.7f;
                    color += materialDiffuse * keylightColor * lightPassed;


                    // secundary light
                    vec3f light2Color = vec3f(0.54f, 0.5f, 0.46f) * 0.7;
                    vec3f light2Dir = vec3f(0.0f, 1.0f, 0.1f).normalized;
                    vec3f eyeDir = vec3f(0.0f, 0f, 1.0f).normalized;
                    float diffuseFactor = dot(normal, light2Dir);

                    if (diffuseFactor > 0)
                        color += materialDiffuse * light2Color * diffuseFactor;

                    // specular
                    vec3f toEye = vec3f(0, 0, 1.0f);
                    vec3f lightReflect = (reflect(light2Dir, normal).normalized);
                    float specularFactor = dot(toEye, lightReflect);
                    if (specularFactor > 0)
                    {
                        specularFactor = specularFactor ^^ 4.0f;
                        color += materialDiffuse * light2Color * specularFactor * 2;
                    }

                    // skybox reflection
                    vec3f pureReflection = (reflect(toEye, normal).normalized);

                    int skyx = cast(int)(0.5 + ((0.5 + pureReflection.x *0.5) * (skybox.w - 1)));
                    int skyy = cast(int)(0.5 + ((0.5 + pureReflection.y *0.5) * (skybox.h - 1)));

                    RGBA skyC = skybox[skyx, skyy];  
                    vec3f skyColor = vec3f(skyC.r / 255.0f, skyC.g / 255.0f, skyC.b / 255.0f);

                    color += 0.15f * skyColor;


                    // Add ambient component
                    vec3f ambientLight = vec3f(0.3f, 0.3f, 0.3f);
                    vec3f materialAmbient = materialDiffuse;
                    //color = vec3f(0.0f);
                    color += colorBleed * ambientLight;

                    // Show normals
                    //color = vec3f(0.5f) + normal * 0.5f;

                    // Show depth
                    {
                        //float depthColor = depthPatch[2][2] / 255.0f;
                        //color = vec3f(depthColor);
                    }

                    // Show diffuse
                    //color = materialDiffuse;

                    // Show AO
                    // color = vec3f(occluded, occluded, occluded);

                    color.x = clamp(color.x, 0.0f, 1.0f);
                    color.y = clamp(color.y, 0.0f, 1.0f);
                    color.z = clamp(color.z, 0.0f, 1.0f);


                    int r = cast(int)(0.5 + color.x * 255);
                    int g = cast(int)(0.5 + color.y * 255);
                    int b = cast(int)(0.5 + color.z * 255);

                    RGBA finalColor = RGBA(cast(ubyte)r, cast(ubyte)g, cast(ubyte)b, 255);
                    wfb[i, j] = finalColor;

                }
            }
        }
    }
}
