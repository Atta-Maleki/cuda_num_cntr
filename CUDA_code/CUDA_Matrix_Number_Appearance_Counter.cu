{"nbformat":4,"nbformat_minor":0,"metadata":{"colab":{"provenance":[{"file_id":"1sc-YnheGsSkEnfMHQWPlB75lMfRngq74","timestamp":1689426386684},{"file_id":"1ztxWAAHDVslWTN2AoNWNJvOpqWsevX5r","timestamp":1684659832337},{"file_id":"1r8uu8yqHQfnmkTfCjVLy4KqgPpZmLjoa","timestamp":1684517224661},{"file_id":"1n1bnGdSrDPjvFrFF9zUSLiX8e0i0nZ0M","timestamp":1684510996155}],"gpuType":"T4","authorship_tag":"ABX9TyMQexNT2H6T50g5AAN2r+Tc"},"kernelspec":{"name":"python3","display_name":"Python 3"},"language_info":{"name":"python"},"accelerator":"GPU"},"cells":[{"cell_type":"code","source":["!apt-get install -y --no-install-recommends"],"metadata":{"colab":{"base_uri":"https://localhost:8080/"},"id":"fiQrTQL4_YbO","executionInfo":{"status":"ok","timestamp":1689515936986,"user_tz":-210,"elapsed":2529,"user":{"displayName":"Atta Maleki","userId":"09673812612104214910"}},"outputId":"1cdaa6d9-419e-4f53-db93-6d87a79e8083"},"execution_count":1,"outputs":[{"output_type":"stream","name":"stdout","text":["Reading package lists... Done\n","Building dependency tree       \n","Reading state information... Done\n","0 upgraded, 0 newly installed, 0 to remove and 15 not upgraded.\n"]}]},{"cell_type":"code","source":["%%writefile bigger3.cu\n","#include <iostream>\n","#include <cuda.h>\n","#include <cuda_runtime.h>\n","#include <cuda_runtime_api.h>\n","#include <cuda_device_runtime_api.h>\n","#include <device_launch_parameters.h>\n","#include <device_functions.h>\n","#include <cooperative_groups.h>\n","#include <ctime>\n","\n","\n","using namespace std;\n","\n","\n","#define width 8192\n","#define NUMS 1024\n","#define width2 (width * width) // 67,108,864\n","#define pixelBlockSize 16\n","#define totalPixelBlocks (width2 / (pixelBlockSize * pixelBlockSize)) // 262,144\n","#define totalThreads totalPixelBlocks // 262,144\n","#define threadPerBlock 8\n","#define GRID (totalThreads / threadPerBlock) // 32,768\n","\n","\n","\n","#define cudaCheckErrors(msg)                         \\\n","    do                                               \\\n","    {                                                \\\n","        cudaError_t __err = cudaGetLastError();      \\\n","        if (__err != cudaSuccess)                    \\\n","        {                                            \\\n","            fprintf(stderr, \"Fatal error: %s (%s at %s:%d)\\n\", \\\n","                    msg, cudaGetErrorString(__err), \\\n","                    __FILE__, __LINE__);            \\\n","            fprintf(stderr, \"*** FAILED - ABORTING\\n\"); \\\n","            exit(1);                                 \\\n","        }                                            \\\n","    } while (0)\n","/////////////////////////////////////////////////////////////////////////////\n","__global__ void first_scenario(int* d_results, short* d_matrix, long size)\n","{\n","    int index = threadIdx.x;\n","    d_results[index] = 0;\n","\n","    for (int i = 0; i < size; i++)\n","    {\n","        int element = d_matrix[i];\n","        if (element == index)\n","        {\n","            d_results[index] = d_results[index] + 1;\n","        }\n","    }\n","}\n","\n","\n","/////////////////////////////////////////////////////////////////////////////\n","__global__ void second_scenario(int* d_results2, int* d_mid, short* d_matrix)\n","{\n","    int tidx = threadIdx.x;\n","\n","    __shared__ int partialCount[threadPerBlock][NUMS];\n","\n","    for (int i = 0; i < NUMS; i++)\n","    {\n","        partialCount[tidx][i] = 0;\n","    }\n","\n","    __syncthreads();\n","\n","    int startIndex = (blockIdx.x * (width2 / GRID)) + (tidx * (pixelBlockSize * pixelBlockSize));\n","    if (startIndex < width2)\n","    {\n","        for (int i = 0; i < (pixelBlockSize * pixelBlockSize); i++)\n","        {\n","            int globalIdx = startIndex + i;\n","            if (globalIdx < width2)\n","            {\n","                int value = d_matrix[globalIdx];\n","                partialCount[tidx][value]++;\n","            }\n","            else\n","                printf(\"globalIdx is out of bound\\n\");\n","        }\n","    }\n","    else\n","        printf(\"startIndex is out of bound\\n\");\n","\n","    __syncthreads();\n","\n","    if (tidx == 0)\n","    {\n","        for (int n = 0; n < NUMS; n++)\n","        {\n","            for (int t = 0; t < threadPerBlock; t++)\n","            {\n","                int midIdx = blockIdx.x * NUMS + n;\n","                atomicAdd(&d_mid[midIdx], partialCount[t][n]);\n","            }\n","        }\n","    }\n","\n","    __syncthreads();\n","\n","    if (tidx == 2 && blockIdx.x == 0)\n","    {\n","        for (int i = 0; i < NUMS; i++)\n","        {\n","            for (int j = 0; j < GRID; j++)\n","            {\n","                int resIndex = i + j * NUMS;\n","                atomicAdd(&d_results2[i], d_mid[resIndex]);\n","            }\n","        }\n","    }\n","}\n","\n","\n","\n","/////////////////////////////////////////////////////////////////////////////\n","/////////////////////////////////////////////////////////////////////////////\n","/////////////////////////////////////////////////////////////////////////////\n","\n","\n","int main()\n","{\n","    short* d_matrix;\n","    int* d_results;\n","\n","\n","    cout << \"CPU Matrix Allocated!\" << endl;\n","\n","    // Allocate and initialize matrix on the host\n","    short* h_matrix = new short[width2];\n","    for (int i = 0; i < width2; i++)\n","    {\n","        h_matrix[i] = rand() % NUMS;\n","    }\n","\n","    // Allocate memory on the device for the matrix\n","    cudaMalloc((void**)&d_matrix, width2 * sizeof(short));\n","    cudaCheckErrors(\"cudaMalloc problem\");\n","\n","    // Copy the matrix from host to device\n","    cudaMemcpy(d_matrix, h_matrix, width2 * sizeof(short), cudaMemcpyHostToDevice);\n","    cudaCheckErrors(\"cudaMemcpy problem\");\n","\n","    cout << \"GPU Matrix Allocated!\" << endl;\n","    cout << endl << \"Random initialization is Done!\" << endl;\n","    cout << \"Data transfer Successful.\" << endl;\n","\n","    // Allocate memory on the device for results\n","    cudaMalloc((void**)&d_results, NUMS * sizeof(int));\n","    cudaCheckErrors(\"cudaMalloc problem\");\n","\n","    // Launch the first scenario kernel\n","    clock_t start1 = clock();\n","    first_scenario<<<1, NUMS>>>(d_results, d_matrix, width2);\n","    cudaCheckErrors(\"kernel_launch problem\");\n","    cudaDeviceSynchronize();\n","    clock_t end1 = clock();\n","    cudaCheckErrors(\"synchronization\");\n","\n","    int* d_results2;\n","    cudaMalloc((void**)&d_results2, NUMS * sizeof(int));\n","    cudaCheckErrors(\"cudaMalloc problem\");\n","\n","    int* d_mid;\n","    int midSize = GRID * NUMS;\n","    cudaMalloc((void**)&d_mid, midSize * sizeof(int));\n","    cudaCheckErrors(\"cudaMalloc problem\");\n","\n","    // Zero-initialize the intermediate results on the device\n","    cudaMemset(d_mid, 0, midSize * sizeof(int));\n","    cudaCheckErrors(\"cudaMemset problem\");\n","\n","    cout << \"Second kernel starts...\" << endl;\n","\n","    // Launch the second scenario kernel\n","    clock_t start = clock();\n","    second_scenario<<<GRID, threadPerBlock>>>(d_results2, d_mid, d_matrix);\n","    cudaCheckErrors(\"kernel_launch problem\");\n","\n","    cudaDeviceSynchronize();\n","    clock_t end = clock();\n","    cudaCheckErrors(\"synchronization\");\n","\n","    cout << \"Second scenario ended\" << endl;\n","\n","    // Copy results from device to host\n","    int* h_results = new int[NUMS];\n","    cudaMemcpy(h_results, d_results, NUMS * sizeof(int), cudaMemcpyDeviceToHost);\n","    cudaCheckErrors(\"cudaMemcpy problem\");\n","\n","    int* h_results2 = new int[NUMS];\n","    cudaMemcpy(h_results2, d_results2, NUMS * sizeof(int), cudaMemcpyDeviceToHost);\n","    cudaCheckErrors(\"cudaMemcpy problem\");\n","\n","    // Print the results\n","    for (int i = 0; i < NUMS; i++)\n","    {\n","        cout << i << \"-\" << h_results[i] << \"-\" << h_results2[i] << endl;\n","    }\n","\n","  float seconds1 = (float)(end1 - start1) / CLOCKS_PER_SEC;\n","\tfloat seconds = (float)(end - start) / CLOCKS_PER_SEC;\n","\n","\tcout << \"First Scenario ended in: \" << seconds1 << endl;\n","\tcout << \"Second Scenario ended in: \" << seconds << endl;\n","\n","    // Free allocated memory on the device\n","    cudaFree(d_matrix);\n","    cudaFree(d_results);\n","    cudaFree(d_results2);\n","    cudaFree(d_mid);\n","\n","    // Free allocated memory on the host\n","    delete[] h_matrix;\n","    delete[] h_results;\n","    delete[] h_results2;\n","\n","    return 0;\n","}\n"],"metadata":{"colab":{"base_uri":"https://localhost:8080/"},"id":"m1UdrIGT_bJ2","executionInfo":{"status":"ok","timestamp":1689516619179,"user_tz":-210,"elapsed":699,"user":{"displayName":"Atta Maleki","userId":"09673812612104214910"}},"outputId":"b1180de5-f5c9-49a8-c316-85eb273fff12"},"execution_count":14,"outputs":[{"output_type":"stream","name":"stdout","text":["Overwriting bigger3.cu\n"]}]},{"cell_type":"code","source":["!nvcc bigger3.cu -o cuda_code_0"],"metadata":{"colab":{"base_uri":"https://localhost:8080/"},"id":"3-AQwnWn_eFD","executionInfo":{"status":"ok","timestamp":1689516623669,"user_tz":-210,"elapsed":2892,"user":{"displayName":"Atta Maleki","userId":"09673812612104214910"}},"outputId":"7ad22850-1f48-433d-d21f-3a3b7e83cb5b"},"execution_count":15,"outputs":[{"output_type":"stream","name":"stdout","text":["In file included from \u001b[01m\u001b[Kbigger3.cu:7\u001b[m\u001b[K:\n","\u001b[01m\u001b[K/usr/local/cuda/bin/../targets/x86_64-linux/include/device_functions.h:54:2:\u001b[m\u001b[K \u001b[01;35m\u001b[Kwarning: \u001b[m\u001b[K#warning \"device_functions.h is an internal header file and must not be used directly.  This file will be removed in a future CUDA release.  Please use cuda_runtime_api.h or cuda_runtime.h instead.\" [\u001b[01;35m\u001b[K-Wcpp\u001b[m\u001b[K]\n","   54 | #\u001b[01;35m\u001b[Kwarning\u001b[m\u001b[K \"device_functions.h is an internal header file and must not be used directly.  This file will be removed in a future CUDA release.  Please use cuda_runtime_api.h or cuda_runtime.h instead.\"\n","      |  \u001b[01;35m\u001b[K^~~~~~~\u001b[m\u001b[K\n","In file included from \u001b[01m\u001b[Kbigger3.cu:7\u001b[m\u001b[K:\n","\u001b[01m\u001b[K/usr/local/cuda/bin/../targets/x86_64-linux/include/device_functions.h:54:2:\u001b[m\u001b[K \u001b[01;35m\u001b[Kwarning: \u001b[m\u001b[K#warning \"device_functions.h is an internal header file and must not be used directly.  This file will be removed in a future CUDA release.  Please use cuda_runtime_api.h or cuda_runtime.h instead.\" [\u001b[01;35m\u001b[K-Wcpp\u001b[m\u001b[K]\n","   54 | #\u001b[01;35m\u001b[Kwarning\u001b[m\u001b[K \"device_functions.h is an internal header file and must not be used directly.  This file will be removed in a future CUDA release.  Please use cuda_runtime_api.h or cuda_runtime.h instead.\"\n","      |  \u001b[01;35m\u001b[K^~~~~~~\u001b[m\u001b[K\n"]}]},{"cell_type":"code","source":["!./cuda_code_0"],"metadata":{"colab":{"base_uri":"https://localhost:8080/"},"id":"xEaxIFJg_fan","executionInfo":{"status":"ok","timestamp":1689516636495,"user_tz":-210,"elapsed":12833,"user":{"displayName":"Atta Maleki","userId":"09673812612104214910"}},"outputId":"3c617e7f-12a8-419f-dcb4-404939d6a23b"},"execution_count":16,"outputs":[{"output_type":"stream","name":"stdout","text":["CPU Matrix Allocated!\n","GPU Matrix Allocated!\n","\n","Random initialization is Done!\n","Data transfer Successful.\n","Second kernel starts...\n","Second scenario ended\n","0-65307-257\n","1-65396-35394\n","2-65758-65758\n","3-65596-65596\n","4-65768-65768\n","5-65299-65299\n","6-65305-65305\n","7-65575-65575\n","8-65389-65389\n","9-65640-65640\n","10-65266-65266\n","11-65374-65374\n","12-65013-65013\n","13-65482-65482\n","14-65215-65215\n","15-65463-65463\n","16-64758-64758\n","17-65351-65351\n","18-65180-65180\n","19-65368-65368\n","20-65355-65355\n","21-65390-65390\n","22-65028-65028\n","23-65542-65542\n","24-65436-65436\n","25-65584-65584\n","26-65535-65535\n","27-65759-65759\n","28-65333-65333\n","29-65856-65856\n","30-65551-65551\n","31-65577-65577\n","32-65920-65920\n","33-65567-65567\n","34-65301-65301\n","35-65828-65828\n","36-65432-65432\n","37-65256-65256\n","38-65661-65661\n","39-65379-65379\n","40-65605-65605\n","41-65517-65517\n","42-65339-65339\n","43-65424-65424\n","44-65376-65376\n","45-65361-65361\n","46-65776-65776\n","47-65344-65344\n","48-65485-65485\n","49-65308-65308\n","50-65147-65147\n","51-65713-65713\n","52-65377-65377\n","53-66135-66135\n","54-64984-64984\n","55-65329-65329\n","56-65573-65573\n","57-65378-65378\n","58-65575-65575\n","59-65059-65059\n","60-65757-65757\n","61-65343-65343\n","62-65222-65222\n","63-65579-65579\n","64-66061-66061\n","65-64975-64975\n","66-65488-65488\n","67-65292-65292\n","68-65628-65628\n","69-65670-65670\n","70-65754-65754\n","71-65598-65598\n","72-64799-64799\n","73-66064-66064\n","74-65284-65284\n","75-65581-65581\n","76-65348-65348\n","77-66024-66024\n","78-65790-65790\n","79-66158-66158\n","80-65657-65657\n","81-65125-65125\n","82-66007-66007\n","83-65662-65662\n","84-65607-65607\n","85-65770-65770\n","86-66115-66115\n","87-65560-65560\n","88-65771-65771\n","89-65255-65255\n","90-64791-64791\n","91-65750-65750\n","92-65978-65978\n","93-65723-65723\n","94-65367-65367\n","95-65503-65503\n","96-65485-65485\n","97-65761-65761\n","98-65483-65483\n","99-65571-65571\n","100-65694-65694\n","101-65496-65496\n","102-65217-65217\n","103-65036-65036\n","104-64993-64993\n","105-66031-66031\n","106-64989-64989\n","107-65487-65487\n","108-65924-65924\n","109-65760-65760\n","110-65281-65281\n","111-65862-65862\n","112-65582-65582\n","113-65235-65235\n","114-65644-65644\n","115-65274-65274\n","116-65401-65401\n","117-65792-65792\n","118-65215-65215\n","119-64734-64734\n","120-65129-65129\n","121-65923-65923\n","122-65383-65383\n","123-65121-65121\n","124-65811-65811\n","125-65267-65267\n","126-65741-65741\n","127-65819-65819\n","128-65717-65717\n","129-65465-65465\n","130-65868-65868\n","131-65223-65223\n","132-65384-65384\n","133-65754-65754\n","134-65645-65645\n","135-65574-65574\n","136-65092-65092\n","137-65544-65544\n","138-65531-65531\n","139-65646-65646\n","140-65655-65655\n","141-65334-65334\n","142-65556-65556\n","143-65963-65963\n","144-65600-65600\n","145-66064-66064\n","146-65560-65560\n","147-65198-65198\n","148-65126-65126\n","149-65525-65525\n","150-65584-65584\n","151-65422-65422\n","152-65446-65446\n","153-65397-65397\n","154-65687-65687\n","155-65231-65231\n","156-65929-65929\n","157-65659-65659\n","158-66167-66167\n","159-65567-65567\n","160-65588-65588\n","161-65339-65339\n","162-65489-65489\n","163-65588-65588\n","164-66464-66464\n","165-65636-65636\n","166-65244-65244\n","167-65511-65511\n","168-65350-65350\n","169-65527-65527\n","170-65380-65380\n","171-65670-65670\n","172-65624-65624\n","173-65944-65944\n","174-65621-65621\n","175-65213-65213\n","176-65830-65830\n","177-65656-65656\n","178-65721-65721\n","179-65621-65621\n","180-65208-65208\n","181-65644-65644\n","182-65660-65660\n","183-65475-65475\n","184-65476-65476\n","185-65368-65368\n","186-65641-65641\n","187-65804-65804\n","188-65635-65635\n","189-65241-65241\n","190-66297-66297\n","191-65420-65420\n","192-65651-65651\n","193-65779-65779\n","194-65428-65428\n","195-65339-65339\n","196-65868-65868\n","197-65766-65766\n","198-65805-65805\n","199-65660-65660\n","200-65464-65464\n","201-65388-65388\n","202-65275-65275\n","203-65341-65341\n","204-65764-65764\n","205-66038-66038\n","206-65460-65460\n","207-65472-65472\n","208-65160-65160\n","209-65246-65246\n","210-65430-65430\n","211-65560-65560\n","212-65484-65484\n","213-65272-65272\n","214-65205-65205\n","215-65441-65441\n","216-65426-65426\n","217-65581-65581\n","218-66009-66009\n","219-65595-65595\n","220-65702-65702\n","221-65408-65408\n","222-65577-65577\n","223-65524-65524\n","224-65363-65363\n","225-65600-65600\n","226-65640-65640\n","227-65721-65721\n","228-65467-65467\n","229-65516-65516\n","230-65320-65320\n","231-65225-65225\n","232-65478-65478\n","233-65846-65846\n","234-66037-66037\n","235-65275-65275\n","236-65365-65365\n","237-65150-65150\n","238-65994-65994\n","239-65464-65464\n","240-65209-65209\n","241-65330-65330\n","242-65009-65009\n","243-65530-65530\n","244-65838-65838\n","245-65368-65368\n","246-65770-65770\n","247-65923-65923\n","248-65484-65484\n","249-65617-65617\n","250-65947-65947\n","251-65673-65673\n","252-65566-65566\n","253-65802-65802\n","254-65709-65709\n","255-65912-65912\n","256-65640-65640\n","257-65258-65258\n","258-65150-65150\n","259-65638-65638\n","260-65785-65785\n","261-65789-65789\n","262-65522-65522\n","263-65562-65562\n","264-65637-65637\n","265-65454-65454\n","266-65312-65312\n","267-66013-66013\n","268-65619-65619\n","269-65853-65853\n","270-65519-65519\n","271-65524-65524\n","272-65430-65430\n","273-65680-65680\n","274-65759-65759\n","275-65601-65601\n","276-64920-64920\n","277-65456-65456\n","278-65699-65699\n","279-66154-66154\n","280-65355-65355\n","281-64975-64975\n","282-66030-66030\n","283-65972-65972\n","284-65668-65668\n","285-65523-65523\n","286-65385-65385\n","287-65238-65238\n","288-65704-65704\n","289-65371-65371\n","290-65633-65633\n","291-65551-65551\n","292-65890-65890\n","293-65193-65193\n","294-65167-65167\n","295-65852-65852\n","296-65667-65667\n","297-65766-65766\n","298-65379-65379\n","299-65764-65764\n","300-65467-65467\n","301-66042-66042\n","302-65796-65796\n","303-65634-65634\n","304-65455-65455\n","305-65106-65106\n","306-65108-65108\n","307-65570-65570\n","308-66009-66009\n","309-65490-65490\n","310-65657-65657\n","311-64894-64894\n","312-65495-65495\n","313-65582-65582\n","314-65468-65468\n","315-65798-65798\n","316-65917-65917\n","317-65226-65226\n","318-65704-65704\n","319-65271-65271\n","320-65841-65841\n","321-65619-65619\n","322-65539-65539\n","323-65911-65911\n","324-65392-65392\n","325-65798-65798\n","326-65428-65428\n","327-65470-65470\n","328-65274-65274\n","329-65853-65853\n","330-65365-65365\n","331-65425-65425\n","332-65419-65419\n","333-65280-65280\n","334-65372-65372\n","335-65561-65561\n","336-65793-65793\n","337-65470-65470\n","338-65547-65547\n","339-65366-65366\n","340-65844-65844\n","341-66044-66044\n","342-65525-65525\n","343-65475-65475\n","344-65439-65439\n","345-65977-65977\n","346-66077-66077\n","347-65375-65375\n","348-65200-65200\n","349-65358-65358\n","350-65150-65150\n","351-65475-65475\n","352-65627-65627\n","353-65600-65600\n","354-65461-65461\n","355-65674-65674\n","356-65390-65390\n","357-65556-65556\n","358-65728-65728\n","359-65902-65902\n","360-65418-65418\n","361-65799-65799\n","362-65681-65681\n","363-65472-65472\n","364-65555-65555\n","365-65470-65470\n","366-65625-65625\n","367-65429-65429\n","368-65475-65475\n","369-65516-65516\n","370-65633-65633\n","371-65736-65736\n","372-66334-66334\n","373-65673-65673\n","374-65613-65613\n","375-65853-65853\n","376-65787-65787\n","377-65568-65568\n","378-65549-65549\n","379-65251-65251\n","380-65374-65374\n","381-65492-65492\n","382-65367-65367\n","383-65600-65600\n","384-65565-65565\n","385-65508-65508\n","386-65844-65844\n","387-65513-65513\n","388-65499-65499\n","389-65150-65150\n","390-64866-64866\n","391-65664-65664\n","392-65592-65592\n","393-65550-65550\n","394-65239-65239\n","395-65103-65103\n","396-65564-65564\n","397-65462-65462\n","398-65497-65497\n","399-65780-65780\n","400-65823-65823\n","401-65789-65789\n","402-65559-65559\n","403-65314-65314\n","404-65813-65813\n","405-65585-65585\n","406-65503-65503\n","407-65852-65852\n","408-65356-65356\n","409-65388-65388\n","410-65516-65516\n","411-65761-65761\n","412-65509-65509\n","413-65723-65723\n","414-65845-65845\n","415-65790-65790\n","416-65590-65590\n","417-65602-65602\n","418-65078-65078\n","419-65004-65004\n","420-65162-65162\n","421-65515-65515\n","422-65417-65417\n","423-65851-65851\n","424-65678-65678\n","425-65264-65264\n","426-65816-65816\n","427-65265-65265\n","428-65612-65612\n","429-65506-65506\n","430-65986-65986\n","431-65406-65406\n","432-65507-65507\n","433-65737-65737\n","434-65081-65081\n","435-65261-65261\n","436-65475-65475\n","437-65201-65201\n","438-65908-65908\n","439-65228-65228\n","440-65328-65328\n","441-64874-64874\n","442-65733-65733\n","443-65368-65368\n","444-65369-65369\n","445-65662-65662\n","446-66051-66051\n","447-65531-65531\n","448-65818-65818\n","449-65586-65586\n","450-65330-65330\n","451-65265-65265\n","452-65401-65401\n","453-65423-65423\n","454-65374-65374\n","455-65227-65227\n","456-65609-65609\n","457-65414-65414\n","458-65003-65003\n","459-65311-65311\n","460-65511-65511\n","461-65905-65905\n","462-65376-65376\n","463-65302-65302\n","464-65470-65470\n","465-65095-65095\n","466-65730-65730\n","467-65688-65688\n","468-65286-65286\n","469-65370-65370\n","470-65331-65331\n","471-65614-65614\n","472-65442-65442\n","473-65421-65421\n","474-65526-65526\n","475-65220-65220\n","476-65608-65608\n","477-65400-65400\n","478-65548-65548\n","479-65689-65689\n","480-65653-65653\n","481-65462-65462\n","482-65818-65818\n","483-65472-65472\n","484-65681-65681\n","485-65217-65217\n","486-65220-65220\n","487-65102-65102\n","488-65472-65472\n","489-65619-65619\n","490-65450-65450\n","491-65840-65840\n","492-65146-65146\n","493-65879-65879\n","494-65887-65887\n","495-65368-65368\n","496-65322-65322\n","497-65594-65594\n","498-65934-65934\n","499-65966-65966\n","500-65472-65472\n","501-65292-65292\n","502-65111-65111\n","503-65784-65784\n","504-65431-65431\n","505-65311-65311\n","506-66097-66097\n","507-64972-64972\n","508-65944-65944\n","509-65400-65400\n","510-65701-65701\n","511-65792-65792\n","512-65459-65459\n","513-65757-65757\n","514-65240-65240\n","515-65752-65752\n","516-64962-64962\n","517-65366-65366\n","518-65701-65701\n","519-65315-65315\n","520-65033-65033\n","521-65472-65472\n","522-65224-65224\n","523-65185-65185\n","524-65479-65479\n","525-65614-65614\n","526-65681-65681\n","527-65265-65265\n","528-65511-65511\n","529-65896-65896\n","530-65950-65950\n","531-65731-65731\n","532-65271-65271\n","533-65765-65765\n","534-65713-65713\n","535-65474-65474\n","536-65498-65498\n","537-65745-65745\n","538-65755-65755\n","539-65463-65463\n","540-65483-65483\n","541-65683-65683\n","542-65925-65925\n","543-65504-65504\n","544-65640-65640\n","545-65328-65328\n","546-65446-65446\n","547-65400-65400\n","548-65426-65426\n","549-65727-65727\n","550-65332-65332\n","551-65323-65323\n","552-65637-65637\n","553-64803-64803\n","554-66086-66086\n","555-65812-65812\n","556-65910-65910\n","557-65461-65461\n","558-65246-65246\n","559-65376-65376\n","560-65675-65675\n","561-65447-65447\n","562-65949-65949\n","563-65413-65413\n","564-65518-65518\n","565-65313-65313\n","566-65129-65129\n","567-65610-65610\n","568-65009-65009\n","569-65699-65699\n","570-66186-66186\n","571-65738-65738\n","572-65368-65368\n","573-65470-65470\n","574-65593-65593\n","575-65453-65453\n","576-65924-65924\n","577-65415-65415\n","578-65270-65270\n","579-65825-65825\n","580-65463-65463\n","581-65716-65716\n","582-64964-64964\n","583-65641-65641\n","584-65559-65559\n","585-65261-65261\n","586-65536-65536\n","587-66004-66004\n","588-65419-65419\n","589-65421-65421\n","590-66032-66032\n","591-65191-65191\n","592-65760-65760\n","593-64950-64950\n","594-65839-65839\n","595-65478-65478\n","596-65626-65626\n","597-65873-65873\n","598-65889-65889\n","599-64993-64993\n","600-65365-65365\n","601-66126-66126\n","602-65070-65070\n","603-65708-65708\n","604-65284-65284\n","605-65729-65729\n","606-65451-65451\n","607-65224-65224\n","608-65478-65478\n","609-65835-65835\n","610-65655-65655\n","611-65470-65470\n","612-65324-65324\n","613-65827-65827\n","614-65700-65700\n","615-65281-65281\n","616-65234-65234\n","617-65493-65493\n","618-65874-65874\n","619-65509-65509\n","620-65482-65482\n","621-65526-65526\n","622-65703-65703\n","623-65569-65569\n","624-65392-65392\n","625-65502-65502\n","626-65595-65595\n","627-65783-65783\n","628-65434-65434\n","629-65361-65361\n","630-65319-65319\n","631-65578-65578\n","632-65754-65754\n","633-65589-65589\n","634-65831-65831\n","635-65475-65475\n","636-65686-65686\n","637-65485-65485\n","638-65689-65689\n","639-65756-65756\n","640-65548-65548\n","641-65138-65138\n","642-66297-66297\n","643-65442-65442\n","644-65694-65694\n","645-65612-65612\n","646-65150-65150\n","647-65502-65502\n","648-65572-65572\n","649-65431-65431\n","650-65594-65594\n","651-65998-65998\n","652-65385-65385\n","653-65638-65638\n","654-65404-65404\n","655-65348-65348\n","656-65434-65434\n","657-65749-65749\n","658-65814-65814\n","659-65016-65016\n","660-65474-65474\n","661-65570-65570\n","662-65743-65743\n","663-65766-65766\n","664-65244-65244\n","665-65262-65262\n","666-65700-65700\n","667-65723-65723\n","668-65733-65733\n","669-65408-65408\n","670-65864-65864\n","671-66005-66005\n","672-65863-65863\n","673-65567-65567\n","674-65461-65461\n","675-65436-65436\n","676-65571-65571\n","677-65969-65969\n","678-65304-65304\n","679-65584-65584\n","680-65763-65763\n","681-65362-65362\n","682-65590-65590\n","683-66060-66060\n","684-65468-65468\n","685-65745-65745\n","686-65949-65949\n","687-65373-65373\n","688-65091-65091\n","689-65603-65603\n","690-65395-65395\n","691-65474-65474\n","692-65860-65860\n","693-65315-65315\n","694-65724-65724\n","695-66030-66030\n","696-66005-66005\n","697-65725-65725\n","698-65685-65685\n","699-65308-65308\n","700-65498-65498\n","701-65690-65690\n","702-65437-65437\n","703-65583-65583\n","704-65287-65287\n","705-65744-65744\n","706-65305-65305\n","707-65792-65792\n","708-65739-65739\n","709-65410-65410\n","710-65456-65456\n","711-65543-65543\n","712-65330-65330\n","713-65872-65872\n","714-65184-65184\n","715-65943-65943\n","716-65548-65548\n","717-66025-66025\n","718-65674-65674\n","719-65604-65604\n","720-65642-65642\n","721-65376-65376\n","722-65872-65872\n","723-65343-65343\n","724-65815-65815\n","725-65570-65570\n","726-65281-65281\n","727-65560-65560\n","728-65397-65397\n","729-65691-65691\n","730-65110-65110\n","731-65729-65729\n","732-66091-66091\n","733-65645-65645\n","734-65442-65442\n","735-65472-65472\n","736-65311-65311\n","737-65914-65914\n","738-65083-65083\n","739-65953-65953\n","740-65343-65343\n","741-64971-64971\n","742-65235-65235\n","743-65384-65384\n","744-65690-65690\n","745-65534-65534\n","746-65643-65643\n","747-65753-65753\n","748-65333-65333\n","749-65421-65421\n","750-65630-65630\n","751-65580-65580\n","752-65437-65437\n","753-65721-65721\n","754-65113-65113\n","755-65033-65033\n","756-65498-65498\n","757-66031-66031\n","758-65522-65522\n","759-65792-65792\n","760-65308-65308\n","761-65532-65532\n","762-65646-65646\n","763-65581-65581\n","764-65370-65370\n","765-65388-65388\n","766-65152-65152\n","767-65652-65652\n","768-65510-65510\n","769-65677-65677\n","770-65485-65485\n","771-66018-66018\n","772-65413-65413\n","773-65110-65110\n","774-65242-65242\n","775-65698-65698\n","776-65320-65320\n","777-65345-65345\n","778-65476-65476\n","779-65658-65658\n","780-66218-66218\n","781-65344-65344\n","782-65574-65574\n","783-65425-65425\n","784-65541-65541\n","785-65334-65334\n","786-65460-65460\n","787-65478-65478\n","788-65363-65363\n","789-65856-65856\n","790-65641-65641\n","791-66067-66067\n","792-65628-65628\n","793-65470-65470\n","794-65408-65408\n","795-65418-65418\n","796-65086-65086\n","797-65130-65130\n","798-65478-65478\n","799-65871-65871\n","800-65477-65477\n","801-65709-65709\n","802-65231-65231\n","803-65712-65712\n","804-65738-65738\n","805-65555-65555\n","806-65777-65777\n","807-65445-65445\n","808-65564-65564\n","809-65678-65678\n","810-65583-65583\n","811-65157-65157\n","812-65624-65624\n","813-65878-65878\n","814-65628-65628\n","815-65457-65457\n","816-65423-65423\n","817-65137-65137\n","818-65316-65316\n","819-65510-65510\n","820-65583-65583\n","821-65418-65418\n","822-65243-65243\n","823-65773-65773\n","824-65961-65961\n","825-65242-65242\n","826-65348-65348\n","827-65386-65386\n","828-65256-65256\n","829-65495-65495\n","830-65418-65418\n","831-65626-65626\n","832-65041-65041\n","833-65226-65226\n","834-66001-66001\n","835-65388-65388\n","836-65248-65248\n","837-65707-65707\n","838-65778-65778\n","839-65801-65801\n","840-65338-65338\n","841-65660-65660\n","842-64995-64995\n","843-65395-65395\n","844-65518-65518\n","845-65688-65688\n","846-65495-65495\n","847-65210-65210\n","848-65774-65774\n","849-65957-65957\n","850-65579-65579\n","851-65704-65704\n","852-65652-65652\n","853-65318-65318\n","854-65990-65990\n","855-65646-65646\n","856-65345-65345\n","857-65932-65932\n","858-65467-65467\n","859-65579-65579\n","860-65690-65690\n","861-65610-65610\n","862-65493-65493\n","863-65572-65572\n","864-65583-65583\n","865-65332-65332\n","866-65652-65652\n","867-65459-65459\n","868-65299-65299\n","869-65348-65348\n","870-65573-65573\n","871-65492-65492\n","872-65291-65291\n","873-65132-65132\n","874-65585-65585\n","875-65749-65749\n","876-65746-65746\n","877-65362-65362\n","878-65666-65666\n","879-65532-65532\n","880-65973-65973\n","881-65755-65755\n","882-65375-65375\n","883-65255-65255\n","884-65287-65287\n","885-65119-65119\n","886-65188-65188\n","887-65132-65132\n","888-65211-65211\n","889-65470-65470\n","890-65855-65855\n","891-65355-65355\n","892-65428-65428\n","893-65360-65360\n","894-65140-65140\n","895-65696-65696\n","896-65785-65785\n","897-65415-65415\n","898-65862-65862\n","899-65672-65672\n","900-65882-65882\n","901-65339-65339\n","902-65503-65503\n","903-65338-65338\n","904-65443-65443\n","905-65660-65660\n","906-65302-65302\n","907-65791-65791\n","908-65469-65469\n","909-66079-66079\n","910-65441-65441\n","911-65485-65485\n","912-65577-65577\n","913-65699-65699\n","914-65321-65321\n","915-65583-65583\n","916-65365-65365\n","917-65317-65317\n","918-65689-65689\n","919-65793-65793\n","920-65900-65900\n","921-65973-65973\n","922-65634-65634\n","923-65706-65706\n","924-65731-65731\n","925-65510-65510\n","926-65687-65687\n","927-65544-65544\n","928-65175-65175\n","929-65658-65658\n","930-65585-65585\n","931-65442-65442\n","932-65267-65267\n","933-65667-65667\n","934-65459-65459\n","935-65746-65746\n","936-65327-65327\n","937-65503-65503\n","938-65137-65137\n","939-65254-65254\n","940-65678-65678\n","941-65794-65794\n","942-65234-65234\n","943-65745-65745\n","944-65662-65662\n","945-65774-65774\n","946-65759-65759\n","947-65470-65470\n","948-65488-65488\n","949-65874-65874\n","950-65279-65279\n","951-65332-65332\n","952-65389-65389\n","953-65683-65683\n","954-65263-65263\n","955-65615-65615\n","956-65484-65484\n","957-65515-65515\n","958-65390-65390\n","959-65603-65603\n","960-65544-65544\n","961-65574-65574\n","962-65238-65238\n","963-65319-65319\n","964-65617-65617\n","965-65503-65503\n","966-65650-65650\n","967-65315-65315\n","968-66093-66093\n","969-66104-66104\n","970-65739-65739\n","971-65716-65716\n","972-65658-65658\n","973-65804-65804\n","974-65522-65522\n","975-65621-65621\n","976-65220-65220\n","977-65648-65648\n","978-65557-65557\n","979-65805-65805\n","980-65892-65892\n","981-65754-65754\n","982-65560-65560\n","983-65462-65462\n","984-65959-65959\n","985-65355-65355\n","986-66037-66037\n","987-65027-65027\n","988-65661-65661\n","989-65386-65386\n","990-65245-65245\n","991-65716-65716\n","992-65472-65472\n","993-65120-65120\n","994-65441-65441\n","995-65405-65405\n","996-65963-65963\n","997-65715-65715\n","998-65083-65083\n","999-66143-66143\n","1000-65708-65708\n","1001-65403-65403\n","1002-65623-65623\n","1003-65486-65486\n","1004-65701-65701\n","1005-65573-65573\n","1006-65145-65145\n","1007-65642-65642\n","1008-65491-65491\n","1009-65133-65133\n","1010-65154-65154\n","1011-65510-65510\n","1012-65618-65618\n","1013-65493-65493\n","1014-65564-65564\n","1015-65288-65288\n","1016-65113-65113\n","1017-66024-66024\n","1018-65243-65243\n","1019-65692-65692\n","1020-65674-65674\n","1021-65255-65255\n","1022-65521-65521\n","1023-65787-65787\n","First Scenario ended in: 5.75677\n","Second Scenario ended in: 5.44124\n"]}]},{"cell_type":"code","source":["!cuda-memcheck ./cuda_code_0"],"metadata":{"colab":{"base_uri":"https://localhost:8080/"},"id":"O66KIUEghjCs","executionInfo":{"status":"ok","timestamp":1684748340757,"user_tz":-210,"elapsed":13,"user":{"displayName":"Atta Maleki","userId":"09673812612104214910"}},"outputId":"283bff1c-ce1b-4c5d-d58c-41157c32c249"},"execution_count":null,"outputs":[{"output_type":"stream","name":"stdout","text":["========= CUDA-MEMCHECK\n","========= This tool is deprecated and will be removed in a future release of the CUDA toolkit\n","========= Please use the compute-sanitizer tool as a drop-in replacement\n","========= Error: Could not find ./cuda_code_0\n","========= ERROR SUMMARY: 0 errors\n"]}]}]}